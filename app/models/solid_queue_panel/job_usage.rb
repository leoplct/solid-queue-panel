# frozen_string_literal: true

module SolidQueuePanel
  # How much CPU and memory a job class used, accumulated in hourly buckets by
  # the recorder so that one row covers thousands of executions.
  #
  # Each hour has one row for the class as a whole, and one row for each set of
  # arguments the recorder saw often enough to be worth remembering: knowing
  # that SyncJob.perform_later(10) takes a minute is worth much more than
  # knowing that SyncJob takes somewhere between a second and an hour.
  class JobUsage < Record
    # Marks the row that totals every run of the class, whatever its arguments.
    ALL_ARGUMENTS = ""

    BUCKET = 1.hour

    scope :in_period, ->(period) { where(bucket_at: period.range) }
    scope :totals, -> { where(arguments_fingerprint: ALL_ARGUMENTS) }
    scope :by_arguments, -> { where.not(arguments_fingerprint: ALL_ARGUMENTS) }

    class << self
      def bucket_for(time)
        Time.at((time.to_i / BUCKET) * BUCKET).utc
      end

      # Adds the totals collected in memory by one process to the shared bucket.
      # An update first, an insert only when the bucket does not exist yet.
      def accumulate(class_name:, bucket_at:, executions:, failures:, cpu_ms:, wall_ms:, memory_growth_kb:, max_rss_kb:,
                     arguments_fingerprint: ALL_ARGUMENTS)
        updated = where(class_name: class_name, arguments_fingerprint: arguments_fingerprint, bucket_at: bucket_at).update_all([
          "executions = executions + ?, failures = failures + ?, cpu_ms = cpu_ms + ?, wall_ms = wall_ms + ?, " \
          "memory_growth_kb = memory_growth_kb + ?, max_rss_kb = CASE WHEN max_rss_kb < ? THEN ? ELSE max_rss_kb END, updated_at = ?",
          executions, failures, cpu_ms, wall_ms, memory_growth_kb, max_rss_kb, max_rss_kb, Time.current
        ])

        return if updated.positive?

        create!(
          class_name: class_name, arguments_fingerprint: arguments_fingerprint, bucket_at: bucket_at,
          executions: executions, failures: failures, cpu_ms: cpu_ms, wall_ms: wall_ms,
          memory_growth_kb: memory_growth_kb, max_rss_kb: max_rss_kb
        )
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def prune(retention)
        where(bucket_at: ...retention.ago).delete_all
      end
    end

    def average_cpu_ms
      executions.positive? ? cpu_ms / executions : 0
    end

    def average_wall_ms
      executions.positive? ? wall_ms / executions : 0
    end
  end
end
