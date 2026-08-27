# frozen_string_literal: true

module SolidQueuePanel
  # Solid Queue models a job's state as the presence of a row in one of the
  # execution tables. This value object gives that implicit state a name, an
  # order and a colour, and is the single place the UI asks "what is this job
  # doing?".
  class JobStatus
    ALL = %i[in_progress queued blocked scheduled failed finished].freeze

    COLORS = {
      in_progress: "blue",
      queued: "indigo",
      blocked: "amber",
      scheduled: "violet",
      failed: "rose",
      finished: "emerald"
    }.freeze

    class << self
      # Derives the status of a job from its executions. Associations are used
      # as-is so that a preloaded relation costs no extra queries.
      def of(job)
        return :finished if job.finished_at.present?
        return :failed if job.failed_execution.present?
        return :in_progress if job.claimed_execution.present?
        return :blocked if job.blocked_execution.present?
        return :scheduled if job.scheduled_execution.present?
        return :queued if job.ready_execution.present?

        :unknown
      end

      def color(status)
        COLORS.fetch(status.to_sym, "slate")
      end

      def label(status)
        I18n.t("solid_queue_panel.statuses.#{status}", default: status.to_s.humanize)
      end
    end
  end
end
