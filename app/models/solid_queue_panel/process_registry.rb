# frozen_string_literal: true

module SolidQueuePanel
  # Reads the registry of running Solid Queue processes: supervisors with their
  # supervisees, what each of them is polling and what they are working on right
  # now.
  class ProcessRegistry
    def processes
      @processes ||= SolidQueue::Process.order(:kind, :name).to_a
    end

    def supervisors
      @supervisors ||= processes.select { |process| process.supervisor_id.nil? }
    end

    def supervisees(process)
      grouped_supervisees.fetch(process.id, [])
    end

    def workers
      @workers ||= processes.select { |process| process.kind == "Worker" }
    end

    def claimed_executions
      @claimed_executions ||= SolidQueue::ClaimedExecution.includes(:job, :process)
        .order(created_at: :asc)
        .to_a
    end

    def busy_count(process)
      busy_counts.fetch(process.id, 0)
    end

    def total_threads
      @total_threads ||= workers.sum { |worker| worker.metadata["thread_pool_size"].to_i }
    end

    def busy_threads
      @busy_threads ||= busy_counts.values.sum
    end

    def utilization
      return 0.0 if total_threads.zero?

      (busy_threads.to_f / total_threads * 100).round(1)
    end

    def alive?(process)
      process.last_heartbeat_at.present? && process.last_heartbeat_at > SolidQueue.process_alive_threshold.ago
    end

    def dead
      @dead ||= processes.reject { |process| alive?(process) }
    end

    def any?
      processes.any?
    end

    private
      def grouped_supervisees
        @grouped_supervisees ||= processes.group_by(&:supervisor_id)
      end

      def busy_counts
        @busy_counts ||= SolidQueue::ClaimedExecution.group(:process_id).count
      end
  end
end
