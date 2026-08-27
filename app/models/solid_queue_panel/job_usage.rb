# frozen_string_literal: true

module SolidQueuePanel
  # How much CPU and memory a job class used, accumulated in hourly buckets by
  # the recorder so that one row covers thousands of executions.
  class JobUsage < Record
    scope :in_period, ->(period) { where(bucket_at: period.range) }

    BUCKET = 1.hour

    class << self
      def bucket_for(time)
        Time.at((time.to_i / BUCKET) * BUCKET).utc
      end

      # Adds the totals collected in memory by one process to the shared bucket.
      # An update first, an insert only when the bucket does not exist yet.
      def accumulate(class_name:, bucket_at:, executions:, failures:, cpu_ms:, wall_ms:, memory_growth_kb:, max_rss_kb:)
        updated = where(class_name: class_name, bucket_at: bucket_at).update_all([
          "executions = executions + ?, failures = failures + ?, cpu_ms = cpu_ms + ?, wall_ms = wall_ms + ?, " \
          "memory_growth_kb = memory_growth_kb + ?, max_rss_kb = CASE WHEN max_rss_kb < ? THEN ? ELSE max_rss_kb END, updated_at = ?",
          executions, failures, cpu_ms, wall_ms, memory_growth_kb, max_rss_kb, max_rss_kb, Time.current
        ])

        return if updated.positive?

        create!(
          class_name: class_name, bucket_at: bucket_at, executions: executions, failures: failures,
          cpu_ms: cpu_ms, wall_ms: wall_ms, memory_growth_kb: memory_growth_kb, max_rss_kb: max_rss_kb
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
