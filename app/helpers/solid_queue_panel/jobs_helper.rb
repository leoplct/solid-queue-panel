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
      arguments_summary(job.arguments.is_a?(Hash) ? job.arguments["arguments"] : nil, limit: limit)
    end

    def arguments_summary(arguments, limit: 120)
      return if arguments.blank?

      truncate(Array(arguments).map { |argument| argument.is_a?(Hash) ? argument.to_json : argument.inspect }.join(", "), length: limit)
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

    # Estimates are read once per request: every running job asks the same
    # object what jobs like it usually take.
    def job_durations
      @job_durations ||= JobDurations.new
    end

    # The progress of a job a worker is running: how long it has been going,
    # against how long jobs like it take. Without an estimate there is no bar,
    # because a bar would be a guess.
    def running_job_progress(execution)
      elapsed = Time.current - execution.created_at
      estimate = execution.job && job_durations.for_job(execution.job)

      return unknown_progress(elapsed) if estimate.nil? || estimate.seconds.to_f <= 0

      progress_bar(
        ratio: elapsed / estimate.seconds,
        label: duration_in_words(elapsed),
        tooltip: progress_tooltip(execution, elapsed, estimate)
      ) + progress_percentage(elapsed, estimate)
    end

    def progress_percentage(elapsed, estimate)
      share = (elapsed / estimate.seconds * 100).round

      tag.span("#{[ share, 999 ].min}%", class: "ml-2 text-xs tabular-nums #{share > 100 ? "text-rose-600 dark:text-rose-400" : "text-slate-500"}")
    end

    def progress_tooltip(execution, elapsed, estimate)
      finishes_at = execution.created_at + estimate.seconds

      [
        if elapsed > estimate.seconds
          "Expected to finish around #{absolute_time(finishes_at)}, so it is taking longer than usual"
        else
          "Expected to finish around #{absolute_time(finishes_at)}"
        end,
        estimate_description(estimate)
      ].join(" · ")
    end

    # Says where the estimate comes from, because "4 minutes" means something
    # different when it is the average of 300 identical runs and when it is the
    # average of the whole class.
    def estimate_description(estimate)
      subject = estimate.by_arguments? ? "runs with the same arguments" : "runs of this job class"
      basis = estimate.measured? ? "measured execution time" : "time from enqueue to completion"

      "estimated from #{number_with_delimiter(estimate.runs)} #{subject} in the last 24 hours (#{basis})"
    end

    def queue_link(queue_name, **options)
      link_to queue_name, queue_path(name: queue_name), **options
    end

    private
      def unknown_progress(elapsed)
        safe_join([
          tag.span(duration_in_words(elapsed), class: "tabular-nums"),
          tag.span("no estimate yet", class: "ml-2 text-xs text-slate-400", title: "No job like this one has finished in the last 24 hours")
        ])
      end
  end
end
