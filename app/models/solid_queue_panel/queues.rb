# frozen_string_literal: true

module SolidQueuePanel
  # The queues of a Solid Queue installation, with the counters of every
  # execution state. The whole collection is built with a handful of grouped
  # queries, so listing fifty queues costs the same as listing one.
  class Queues
    include Enumerable

    # How a job that has never failed looks in the Active Job payload Solid
    # Queue stores as JSON.
    FIRST_ATTEMPT = "%\"executions\":0%"

    def each(&block)
      summaries.each(&block)
    end

    def find_by_name(name)
      build(name)
    end

    def size
      summaries.size
    end

    private
      def summaries
        @summaries ||= names.map { |name| build(name) }.sort_by { |queue| [ -queue.ready, queue.name ] }
      end

      # Queue names are collected from every place they can show up, so that a
      # queue that is configured but currently empty is still listed.
      def names
        [
          ready_counts.keys,
          scheduled_counts.keys,
          blocked_counts.keys,
          paused_names,
          SolidQueue::RecurringTask.distinct.pluck(:queue_name),
          polled_names
        ].flatten.compact_blank.uniq.sort
      end

      def build(name)
        QueueSummary.new(
          name: name,
          ready: ready_counts.fetch(name, 0),
          scheduled: scheduled_counts.fetch(name, 0),
          blocked: blocked_counts.fetch(name, 0),
          in_progress: in_progress_counts.fetch(name, 0),
          failed: failed_counts.fetch(name, 0),
          retries: retry_counts.fetch(name, 0),
          oldest_enqueued_at: oldest_enqueued_ats[name],
          newest_enqueued_at: newest_enqueued_ats[name],
          paused: paused_names.include?(name)
        )
      end

      def ready_counts
        @ready_counts ||= SolidQueue::ReadyExecution.group(:queue_name).count
      end

      def scheduled_counts
        @scheduled_counts ||= SolidQueue::ScheduledExecution.group(:queue_name).count
      end

      def blocked_counts
        @blocked_counts ||= SolidQueue::BlockedExecution.group(:queue_name).count
      end

      def in_progress_counts
        @in_progress_counts ||= SolidQueue::ClaimedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
      end

      def failed_counts
        @failed_counts ||= SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
      end

      # Jobs waiting to run that have already raised at least once. Active Job
      # counts the attempts in the payload it hands to Solid Queue and bumps
      # `executions` before scheduling the next try, so the payload is matched
      # as the text it is stored as: it is a serialized column, and comparing it
      # through Active Record would serialize the pattern too.
      def retry_counts
        @retry_counts ||= SolidQueue::Job
          .where(id: SolidQueue::ReadyExecution.select(:job_id))
          .or(SolidQueue::Job.where(id: SolidQueue::ScheduledExecution.select(:job_id)))
          .where.not("#{SolidQueue::Job.quoted_table_name}.arguments LIKE ?", FIRST_ATTEMPT)
          .group(:queue_name)
          .count
      end

      def oldest_enqueued_ats
        @oldest_enqueued_ats ||= SolidQueue::ReadyExecution.group(:queue_name).minimum(:created_at)
      end

      def newest_enqueued_ats
        @newest_enqueued_ats ||= SolidQueue::ReadyExecution.group(:queue_name).maximum(:created_at)
      end

      def paused_names
        @paused_names ||= SolidQueue::Pause.pluck(:queue_name)
      end

      # Queues the running workers are polling, wildcards excluded: those are
      # patterns, not queues.
      def polled_names
        @polled_names ||= SolidQueue::Process.where(kind: "Worker").filter_map { |process| process.metadata["queues"] }
          .flat_map { |queues| queues.to_s.split(",") }
          .map(&:strip)
          .reject { |queue| queue.include?("*") }
      end
  end
end
