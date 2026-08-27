# frozen_string_literal: true

module SolidQueuePanel
  # Aggregated counters for the stat bar that sits on top of every page. Every
  # counter is memoized so a page render only hits the database once per figure.
  class Overview
    FINISHED_WINDOW = 24.hours

    def in_progress
      @in_progress ||= SolidQueue::ClaimedExecution.count
    end

    def queued
      @queued ||= SolidQueue::ReadyExecution.count
    end

    def scheduled
      @scheduled ||= SolidQueue::ScheduledExecution.count
    end

    def blocked
      @blocked ||= SolidQueue::BlockedExecution.count
    end

    def failed
      @failed ||= SolidQueue::FailedExecution.count
    end

    # Finished jobs are pruned periodically by the dispatcher, so this is always
    # a rolling window rather than an all-time counter. It is also the only
    # counter that could scan a large table, hence the time constraint that lets
    # the index on +finished_at+ do the work.
    def finished
      @finished ||= SolidQueue::Job.where(finished_at: FINISHED_WINDOW.ago..).count
    end

    def processes
      @processes ||= SolidQueue::Process.count
    end

    def workers
      @workers ||= SolidQueue::Process.where(kind: "Worker").count
    end

    def paused_queues
      @paused_queues ||= SolidQueue::Pause.count
    end

    def dead_processes
      @dead_processes ||= SolidQueue::Process.prunable.count
    end

    def recurring_tasks
      @recurring_tasks ||= SolidQueue::RecurringTask.count
    end

    def oldest_enqueued_at
      return @oldest_enqueued_at if defined?(@oldest_enqueued_at)

      @oldest_enqueued_at = SolidQueue::ReadyExecution.minimum(:created_at)
    end

    # Seconds the oldest queued job has been waiting: the single number that
    # tells you whether the workers are keeping up.
    def latency
      @latency ||= oldest_enqueued_at ? (Time.current - oldest_enqueued_at).to_i : 0
    end
  end
end
