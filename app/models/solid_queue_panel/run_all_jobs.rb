# frozen_string_literal: true

module SolidQueuePanel
  # Puts every job of a list back to work, whatever is keeping it from running:
  #
  # - failed jobs are enqueued again, with their attempt counters reset;
  # - scheduled jobs become due now, so the dispatcher picks them up on its next
  #   poll;
  # - blocked jobs are offered their concurrency lock again, and the ones that
  #   can take it start running. The ones that cannot stay blocked: this asks
  #   Solid Queue to try, it does not go around the limit.
  #
  # The list is whatever the page is showing, filters included, and it is
  # bounded: a queue with a hundred thousand failures is worked through a few
  # thousand at a time rather than in one request that never returns.
  class RunAllJobs
    MAX = 5_000
    BATCH = 500

    STATUSES = %w[failed scheduled blocked].freeze

    Result = Struct.new(:status, :count, :attempted, :capped) do
      def capped?
        capped
      end

      def any?
        count.positive?
      end

      # Blocked jobs that could not take their concurrency lock this time.
      def left_behind
        attempted - count
      end
    end

    def initialize(query)
      @query = query
    end

    def available?
      STATUSES.include?(query.status)
    end

    def run
      return Result.new(query.status, 0, 0, false) unless available?

      ids = query.scope.limit(MAX).pluck(:id)
      count = ids.each_slice(BATCH).sum { |slice| run_batch(slice) }

      Result.new(query.status, count, ids.size, ids.size >= MAX)
    end

    private
      attr_reader :query

      def run_batch(ids)
        case query.status
        when "failed" then retry_failed(ids)
        when "scheduled" then dispatch_scheduled(ids)
        when "blocked" then release_blocked(ids)
        else 0
        end
      end

      # Retrying one job through Solid Queue resets its attempt counters, while
      # retrying many does not, so they are reset here: a job put back by hand
      # should get the same fresh start whether it went back alone or with a
      # thousand others.
      def retry_failed(ids)
        failed = SolidQueue::Job.where(id: ids).joins(:failed_execution)
        count = failed.count
        return 0 if count.zero?

        failed.find_each(&:reset_execution_counters)
        SolidQueue::FailedExecution.retry_all(SolidQueue::Job.where(id: ids))

        count
      end

      # Moving the due date is all it takes: the dispatcher polls for jobs whose
      # time has come, so the jobs go through the usual concurrency checks
      # rather than around them.
      def dispatch_scheduled(ids)
        now = Time.current

        SolidQueue::Job.transaction do
          SolidQueue::ScheduledExecution.where(job_id: ids).update_all(scheduled_at: now)
          SolidQueue::Job.where(id: ids).update_all(scheduled_at: now, updated_at: now)
        end
      end

      def release_blocked(ids)
        SolidQueue::BlockedExecution.where(job_id: ids).includes(:job).count do |execution|
          execution.release
          execution.destroyed?
        end
      end
  end
end
