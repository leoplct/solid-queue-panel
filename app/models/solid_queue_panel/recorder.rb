# frozen_string_literal: true

module SolidQueuePanel
  # Records, from inside every Solid Queue process, how much memory and CPU that
  # process and its machine are using, and how much of it each job class is
  # responsible for.
  #
  # A timer thread writes one row per process every few seconds. Job usage is
  # accumulated in memory as jobs run and flushed on the same tick, so a busy
  # worker adds a handful of queries a minute rather than one per job.
  #
  # Nothing is recorded until the tables are installed with
  # `bin/rails generate solid_queue_panel:resource_metrics`.
  class Recorder
    JOB_EVENT = "perform.active_job"
    PRUNE_EVERY = 120

    # Sets of arguments to remember per class and per flush. Jobs called with a
    # different argument every time would otherwise write one row per run, so
    # only the most frequent ones of each tick are kept; the total of the class
    # is always written.
    MAX_ARGUMENT_SETS = 25

    class << self
      def start(kind:)
        return if @recorder || !SolidQueuePanel.resource_metrics?

        @recorder = new(kind: kind).tap(&:start)
      rescue StandardError => error
        report(error)
        nil
      end

      def stop
        @recorder&.stop
        @recorder = nil
      rescue StandardError => error
        report(error)
      end

      def recording?
        @recorder.present?
      end

      def report(error)
        SolidQueue.on_thread_error&.call(error)
      end
    end

    def initialize(kind:, machine: Machine.new, configuration: SolidQueuePanel.configuration)
      @kind = kind
      @machine = machine
      @configuration = configuration
      @usage = Hash.new { |usage, key| usage[key] = new_usage }
      @mutex = Mutex.new
      @ticks = 0
      @cpu_time = machine.process_cpu_time
      @cpu_measured_at = monotonic_time
    end

    def start
      subscribe_to_jobs if kind == "Worker"

      @timer = Concurrent::TimerTask.new(execution_interval: configuration.resource_sample_interval.to_i, run_now: false) do
        wrap_in_app_executor { tick }
      end
      @timer.add_observer { |_time, _result, error| self.class.report(error) if error }
      @timer.execute
    end

    def stop
      @timer&.shutdown
      ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
      @subscription = nil
      wrap_in_app_executor { flush_job_usage }
    end

    # Called by the subscriber once per job execution, on the thread that ran it.
    def track(class_name:, arguments_fingerprint:, cpu_ms:, wall_ms:, memory_growth_kb:, rss_kb:, failed:)
      mutex.synchronize do
        usage = @usage[[ class_name, arguments_fingerprint.to_s ]]
        usage[:executions] += 1
        usage[:failures] += 1 if failed
        usage[:cpu_ms] += cpu_ms
        usage[:wall_ms] += wall_ms
        usage[:memory_growth_kb] += memory_growth_kb
        usage[:max_rss_kb] = rss_kb if rss_kb > usage[:max_rss_kb]
      end
    end

    # Takes one reading and writes down the job usage collected since the last
    # one. Called by the timer, and by the tests.
    def tick
      record_sample
      flush_job_usage
      prune_periodically
    end

    private
      attr_reader :kind, :machine, :configuration, :mutex

      def record_sample
        ProcessSample.create!(
          process_id: solid_queue_process_id,
          name: process_name,
          kind: kind,
          hostname: machine.hostname,
          pid: Process.pid,
          rss_kb: machine.rss_kb,
          cpu_percent: cpu_percent,
          threads: Thread.list.count(&:alive?),
          cpu_count: machine.cpu_count,
          load_average: machine.load_average,
          memory_kb: machine.memory_kb,
          available_memory_kb: machine.available_memory_kb,
          created_at: Time.current
        )
      end

      # CPU used since the previous sample, as a percentage of one core: 100%
      # means this process kept one core busy the whole interval.
      def cpu_percent
        now = monotonic_time
        cpu_time = machine.process_cpu_time
        elapsed = now - @cpu_measured_at

        percent = elapsed.positive? ? (cpu_time - @cpu_time) / elapsed * 100 : 0.0
        @cpu_time = cpu_time
        @cpu_measured_at = now

        percent.round(2)
      end

      def flush_job_usage
        pending = mutex.synchronize do
          collected = @usage
          @usage = Hash.new { |usage, key| usage[key] = new_usage }
          collected
        end

        bucket_at = JobUsage.bucket_for(Time.current)

        class_totals(pending).each do |class_name, usage|
          JobUsage.accumulate(class_name: class_name, bucket_at: bucket_at, **usage)
        end

        frequent_argument_sets(pending).each do |(class_name, fingerprint), usage|
          JobUsage.accumulate(class_name: class_name, arguments_fingerprint: fingerprint, bucket_at: bucket_at, **usage)
        end
      end

      def class_totals(pending)
        pending.each_with_object(Hash.new { |totals, class_name| totals[class_name] = new_usage }) do |((class_name, _fingerprint), usage), totals|
          merge_usage(totals[class_name], usage)
        end
      end

      def frequent_argument_sets(pending)
        pending
          .reject { |(_class_name, fingerprint), _usage| fingerprint.blank? }
          .group_by { |(class_name, _fingerprint), _usage| class_name }
          .flat_map { |_class_name, entries| entries.max_by(MAX_ARGUMENT_SETS) { |_key, usage| usage[:executions] } }
          .to_h
      end

      def merge_usage(into, usage)
        into[:executions] += usage[:executions]
        into[:failures] += usage[:failures]
        into[:cpu_ms] += usage[:cpu_ms]
        into[:wall_ms] += usage[:wall_ms]
        into[:memory_growth_kb] += usage[:memory_growth_kb]
        into[:max_rss_kb] = usage[:max_rss_kb] if usage[:max_rss_kb] > into[:max_rss_kb]
        into
      end

      def prune_periodically
        @ticks += 1
        return unless (@ticks % PRUNE_EVERY).zero?

        ProcessSample.prune(configuration.resource_retention)
        JobUsage.prune(configuration.resource_retention)
      end

      def subscribe_to_jobs
        @subscription = ActiveSupport::Notifications.subscribe(JOB_EVENT, JobSubscriber.new(self, machine))
      end

      # The row Solid Queue registered for this process, so the panel can show
      # the samples next to it. It may not exist yet on the first tick.
      def solid_queue_process_id
        @solid_queue_process_id ||= SolidQueue::Process.where(hostname: machine.hostname, pid: Process.pid).pick(:id)
      end

      def process_name
        @process_name ||= SolidQueue::Process.where(hostname: machine.hostname, pid: Process.pid).pick(:name) ||
                          "#{kind.downcase}-#{Process.pid}"
      end

      def new_usage
        { executions: 0, failures: 0, cpu_ms: 0, wall_ms: 0, memory_growth_kb: 0, max_rss_kb: 0 }
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def wrap_in_app_executor(&block)
        SolidQueue.app_executor ? SolidQueue.app_executor.wrap(&block) : block.call
      end

      # Measures one job execution. Active Support calls #start and #finish on
      # the thread running the job, so the CPU time is that thread's alone.
      # Memory is not: RSS belongs to the whole process, so with several threads
      # the growth attributed to a job is an indication, not an invoice.
      class JobSubscriber
        STACK_KEY = :solid_queue_panel_job_measurements

        def initialize(recorder, machine)
          @recorder = recorder
          @machine = machine
        end

        def start(_name, _id, _payload)
          measurements.push([ Machine.thread_cpu_time, monotonic_time, @machine.rss_kb ])
        end

        def finish(_name, _id, payload)
          started = measurements.pop
          return unless started

          cpu, clock, rss = started
          current_rss = @machine.rss_kb

          @recorder.track(
            class_name: payload[:job].class.name,
            arguments_fingerprint: ArgumentsFingerprint.for(payload[:job]),
            cpu_ms: ((Machine.thread_cpu_time - cpu) * 1000).round,
            wall_ms: ((monotonic_time - clock) * 1000).round,
            memory_growth_kb: [ current_rss - rss, 0 ].max,
            rss_kb: current_rss,
            failed: payload[:exception].present?
          )
        rescue StandardError => error
          Recorder.report(error)
        end

        private
          def measurements
            Thread.current[STACK_KEY] ||= []
          end

          def monotonic_time
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
      end
  end
end
