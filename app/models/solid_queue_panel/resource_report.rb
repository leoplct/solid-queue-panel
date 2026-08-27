# frozen_string_literal: true

module SolidQueuePanel
  # Reads back what the recorder wrote: how much memory and CPU each machine and
  # each Solid Queue process is using, how that moved over time, and which job
  # classes are responsible for it.
  class ResourceReport
    HEAVIEST_JOBS = 10
    CURRENT_WITHIN = 5.minutes

    # One machine (or container) running Solid Queue processes, as described by
    # the most recent sample of each of its processes.
    class Host
      attr_reader :hostname, :samples

      def initialize(hostname:, samples:, thread_pools: {})
        @hostname = hostname
        @samples = samples
        @thread_pools = thread_pools
      end

      def latest
        @latest ||= samples.max_by(&:created_at)
      end

      def workers
        @workers ||= samples.select { |sample| sample.kind == "Worker" }
      end

      def cpu_count
        latest.cpu_count
      end

      def load_average
        latest.load_average
      end

      def load_per_core
        latest.load_per_core
      end

      def memory_kb
        latest.memory_kb
      end

      def available_memory_kb
        latest.available_memory_kb
      end

      def used_memory_kb
        latest.used_memory_kb
      end

      def memory_usage
        latest.memory_usage
      end

      # Memory the Solid Queue processes themselves are holding, as opposed to
      # everything else running on the machine.
      def solid_queue_memory_kb
        samples.sum(&:rss_kb)
      end

      def worker_memory_kb
        workers.any? ? workers.sum(&:rss_kb) / workers.size : 0
      end

      # CPU the Solid Queue processes are using, as a percentage of one core.
      def cpu_percent
        samples.sum { |sample| sample.cpu_percent.to_f }
      end

      # The same figure against everything the machine has: 100% would mean
      # Solid Queue is using every core.
      def machine_cpu_usage
        return unless cpu_count.to_i.positive?

        cpu_percent / cpu_count
      end

      # Threads each worker is configured with, from the Solid Queue process
      # registry rather than from the sample: what matters for tuning is the
      # pool size, not how many Ruby threads happen to be alive.
      def threads_per_worker
        @threads_per_worker ||= workers.filter_map { |worker| @thread_pools[worker.name] }.max
      end

      def total_worker_threads
        threads_per_worker ? threads_per_worker * workers.size : nil
      end

      def advice
        @advice ||= TuningAdvice.new(self)
      end
    end

    Usage = Struct.new(:class_name, :executions, :failures, :cpu_ms, :wall_ms, :memory_growth_kb, :max_rss_kb) do
      def average_cpu_ms
        executions.positive? ? cpu_ms / executions : 0
      end

      def average_wall_ms
        executions.positive? ? wall_ms / executions : 0
      end

      def average_memory_growth_kb
        executions.positive? ? memory_growth_kb / executions : 0
      end

      def cpu_share_of(total)
        total.positive? ? (cpu_ms.to_f / total * 100).round(1) : 0.0
      end
    end

    attr_reader :period

    def initialize(period: TimePeriod.default)
      @period = TimePeriod.wrap(period)
    end

    def installed?
      SolidQueuePanel.resource_metrics?
    end

    def any?
      installed? && current_samples.any?
    end

    def hosts
      @hosts ||= current_samples.group_by(&:hostname).map do |hostname, samples|
        Host.new(hostname: hostname, samples: samples, thread_pools: thread_pools)
      end.sort_by(&:hostname)
    end

    def recorded_at
      current_samples.map(&:created_at).max
    end

    # Memory the machine is using, in MB, averaged over each bucket of the
    # period. Every sample carries the figure, so averaging is meaningful
    # however many processes reported.
    def machine_memory_series(host)
      rows = ProcessSample.on_host(host.hostname).in_period(period).pluck(:created_at, :memory_kb, :available_memory_kb)

      bucketed(rows.filter_map { |time, total, available| [ time, (total - available) / 1024.0 ] if total && available })
    end

    def worker_memory_series(host)
      average_series(ProcessSample.on_host(host.hostname).workers, :rss_kb) { |value| value / 1024.0 }
    end

    def worker_cpu_series(host)
      average_series(ProcessSample.on_host(host.hostname).workers, :cpu_percent)
    end

    def load_series(host)
      average_series(ProcessSample.on_host(host.hostname), :load_average)
    end

    def heaviest_jobs(limit: HEAVIEST_JOBS)
      @heaviest_jobs ||= JobUsage.in_period(period)
        .group(:class_name)
        .pluck(
          :class_name,
          Arel.sql("SUM(executions)"), Arel.sql("SUM(failures)"), Arel.sql("SUM(cpu_ms)"),
          Arel.sql("SUM(wall_ms)"), Arel.sql("SUM(memory_growth_kb)"), Arel.sql("MAX(max_rss_kb)")
        )
        .map { |row| Usage.new(*row) }
        .sort_by { |usage| -usage.cpu_ms }
        .first(limit)
    end

    def total_cpu_ms
      @total_cpu_ms ||= heaviest_jobs.sum(&:cpu_ms)
    end

    def job_usage?
      heaviest_jobs.any?
    end

    private
      def current_samples
        @current_samples ||= installed? ? ProcessSample.latest_per_process(within: CURRENT_WITHIN) : []
      end

      def thread_pools
        @thread_pools ||= SolidQueue::Process.where(kind: "Worker").to_h do |process|
          [ process.name, process.metadata["thread_pool_size"] ]
        end
      end

      def average_series(relation, column)
        rows = relation.in_period(period).where.not(column => nil).pluck(:created_at, column)
        rows = rows.map { |time, value| [ time, yield(value) ] } if block_given?

        bucketed(rows)
      end

      def bucketed(rows)
        bucket = TimeBucket.new(period.bucket_size)
        grouped = rows.group_by { |time, _value| bucket.index_for(time) }

        (bucket.index_for(period.starts_at)..bucket.index_for(period.ends_at)).map do |index|
          values = grouped[index]&.map(&:last)

          [ bucket.time_for(index), values.present? ? values.sum / values.size : nil ]
        end
      end
  end
end
