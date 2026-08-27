# frozen_string_literal: true

module SolidQueuePanel
  module JobsHelper
    STATUS_ICONS = {
      in_progress: "bolt",
      queued: "queue-list",
      blocked: "lock-closed",
      scheduled: "clock",
      failed: "exclamation-triangle",
      finished: "check-circle",
      unknown: "ellipsis-horizontal"
    }.freeze

    def status_label(status)
      JobStatus.label(status)
    end

    def job_status(job)
      JobStatus.of(job)
    end

    def job_status_badge(job, status: nil)
      status = (status || job_status(job)).to_sym

      badge(JobStatus.label(status), color: JobStatus.color(status), icon_name: STATUS_ICONS[status])
    end

    def job_status_tabs
      [
        [ "all", "All", nil ],
        [ "in_progress", "In progress", overview.in_progress ],
        [ "queued", "Queued", overview.queued ],
        [ "scheduled", "Scheduled", overview.scheduled ],
        [ "blocked", "Blocked", overview.blocked ],
        [ "failed", "Failed", overview.failed ],
        [ "finished", "Finished", overview.finished ]
      ]
    end

    # The Active Job payload as stored by Solid Queue, pretty printed.
    def job_payload(job)
      JSON.pretty_generate(job.arguments)
    rescue StandardError
      job.arguments.inspect
    end

    # Just the positional arguments the job was enqueued with, which is what you
    # usually want to see in a list.
    def job_arguments_summary(job, limit: 120)
      arguments = job.arguments.is_a?(Hash) ? job.arguments["arguments"] : nil
      return if arguments.blank?

      truncate(arguments.map { |argument| argument.is_a?(Hash) ? argument.to_json : argument.inspect }.join(", "), length: limit)
    end

    def job_attempts(job)
      job.arguments.is_a?(Hash) ? job.arguments["executions"].to_i : 0
    end

    # How long the job has been running, or how long it took to complete.
    def job_runtime(job)
      if job.finished_at? then job.finished_at - job.created_at
      elsif job.claimed_execution then Time.current - job.claimed_execution.created_at
      end
    end

    def job_due_at(job)
      job.scheduled_execution&.scheduled_at || job.scheduled_at
    end

    def failed_error_class(failed_execution)
      failed_execution&.exception_class.presence || "Error"
    end

    def failed_error_message(failed_execution)
      failed_execution&.message.presence || "No message recorded"
    end

    def failed_backtrace(failed_execution)
      Array(failed_execution&.backtrace)
    end

    def queue_link(queue_name, **options)
      link_to queue_name, queue_path(name: queue_name), **options
    end
  end
end
