# frozen_string_literal: true

module SolidQueuePanel
  # The operational view of the queues: how many jobs each one can run at once,
  # how many it is running, how many are waiting, and when it will be empty.
  #
  # Capacity is the number of worker threads polling a queue. A worker polling
  # several queues lends its threads to all of them, so capacities can overlap:
  # what the number says is how many jobs of that queue *could* be running at
  # this moment, not how many are reserved for it.
  class QueueCapacity
    Row = Struct.new(:name, :capacity, :in_progress, :pending, :retries, :scheduled, :dead, :last_enqueued_at,
                     :work_seconds, :unknown_jobs, :paused, keyword_init: true) do
      def paused?
        paused
      end

      def utilization
        capacity.positive? ? (in_progress.to_f / capacity * 100) : 0.0
      end

      def backlog
        in_progress + pending
      end

      def idle?
        backlog.zero?
      end

      # Seconds before the queue is empty, if nothing else is enqueued: the work
      # waiting, spread over the threads that can pick it up. Nil when none of
      # the jobs waiting has ever been seen before.
      def eta_seconds
        return if idle? || !workable? || work_seconds.zero?

        work_seconds / capacity
      end

      # Some of the jobs waiting have no history, so the estimate is a floor
      # rather than an answer.
      def partial_eta?
        unknown_jobs.positive? && eta_seconds.present?
      end

      def unknown_eta?
        !idle? && workable? && eta_seconds.nil?
      end

      def workable?
        capacity.positive? && !paused?
      end
    end

    ZERO_WORK = { seconds: 0.0, unknown: 0 }.freeze

    def initialize(queues: Queues.new, durations: JobDurations.new, trends: QueueTrends.new)
      @queues = queues
      @durations = durations
      @trends = trends
    end

    # The last day of a queue, hour by hour, for the sparkline next to its name.
    def trend_for(queue_name)
      trends.for(queue_name)
    end

    def trend_summary(queue_name)
      "#{ActiveSupport::NumberHelper.number_to_delimited(trends.enqueued(queue_name))} enqueued and " \
        "#{ActiveSupport::NumberHelper.number_to_delimited(trends.finished(queue_name))} finished in the last #{trends.period.label}"
    end

    def trend?(queue_name)
      trends.any?(queue_name)
    end

    def rows
      @rows ||= queues.map { |queue| build_row(queue) }.sort_by { |row| [ -row.backlog, row.name ] }
    end

    def any?
      rows.any?
    end

    def total_capacity
      @total_capacity ||= worker_pools.sum { |pool| pool[:threads] }
    end

    def busiest_eta
      rows.filter_map(&:eta_seconds).max
    end

    def durations_basis
      durations.basis
    end

    private
      attr_reader :queues, :durations, :trends

      def build_row(queue)
        Row.new(
          name: queue.name,
          capacity: capacity_for(queue.name),
          in_progress: queue.in_progress,
          pending: queue.ready,
          retries: queue.retries,
          scheduled: queue.scheduled,
          dead: queue.failed,
          last_enqueued_at: queue.newest_enqueued_at,
          work_seconds: work.fetch(queue.name, ZERO_WORK)[:seconds],
          unknown_jobs: work.fetch(queue.name, ZERO_WORK)[:unknown],
          paused: queue.paused?
        )
      end

      # Threads of every worker whose queue list covers this queue, wildcards
      # included, the way Solid Queue itself resolves them.
      def capacity_for(queue_name)
        worker_pools.sum { |pool| pool[:patterns].any? { |pattern| matches?(pattern, queue_name) } ? pool[:threads] : 0 }
      end

      def matches?(pattern, queue_name)
        return true if pattern == "*"
        return queue_name.start_with?(pattern.delete_suffix("*")) if pattern.end_with?("*")

        pattern == queue_name
      end

      def worker_pools
        @worker_pools ||= SolidQueue::Process.where(kind: "Worker").map do |process|
          {
            patterns: process.metadata["queues"].to_s.split(",").map(&:strip).presence || [ "*" ],
            threads: process.metadata["thread_pool_size"].to_i
          }
        end
      end

      # Work waiting in each queue, in seconds, and how many of the jobs there
      # have never been seen before and could not be estimated.
      def work
        @work ||= pending_by_class.transform_values do |counts|
          counts.each_with_object({ seconds: 0.0, unknown: 0 }) do |(class_name, count), totals|
            if (seconds = durations.average_seconds(class_name))
              totals[:seconds] += seconds * count
            else
              totals[:unknown] += count
            end
          end
        end
      end

      # Jobs waiting or running, by queue and class, so the estimate uses the
      # duration of the jobs that are actually there rather than an average of
      # everything.
      def pending_by_class
        @pending_by_class ||= begin
          counts = Hash.new { |hash, queue| hash[queue] = Hash.new(0) }

          [ ready_counts, claimed_counts ].each do |source|
            source.each { |(queue_name, class_name), count| counts[queue_name][class_name] += count }
          end

          counts
        end
      end

      def ready_counts
        SolidQueue::Job.where(id: SolidQueue::ReadyExecution.select(:job_id)).group(:queue_name, :class_name).count
      end

      def claimed_counts
        SolidQueue::Job.joins(:claimed_execution).group(:queue_name, :class_name).count
      end
  end
end
