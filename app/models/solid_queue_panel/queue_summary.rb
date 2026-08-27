# frozen_string_literal: true

module SolidQueuePanel
  # Everything the queues page shows about a single queue. Summaries are built
  # by Queues, which collects the counters for every queue at once.
  class QueueSummary
    attr_reader :name, :ready, :scheduled, :blocked, :in_progress, :failed, :oldest_enqueued_at

    def initialize(name:, ready: 0, scheduled: 0, blocked: 0, in_progress: 0, failed: 0, oldest_enqueued_at: nil, paused: false)
      @name = name
      @ready = ready
      @scheduled = scheduled
      @blocked = blocked
      @in_progress = in_progress
      @failed = failed
      @oldest_enqueued_at = oldest_enqueued_at
      @paused = paused
    end

    alias size ready

    def paused?
      @paused
    end

    def pending
      ready + scheduled + blocked
    end

    # Seconds the oldest job in the queue has been waiting to be picked up.
    def latency
      @latency ||= oldest_enqueued_at ? (Time.current - oldest_enqueued_at).to_i : 0
    end

    def empty?
      pending.zero? && in_progress.zero?
    end
  end
end
