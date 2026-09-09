# frozen_string_literal: true

module SolidQueuePanel
  # Everything the panel can change is written down: which action, who asked for
  # it, from where, and what it touched. The panel pauses queues and discards
  # jobs, so "someone discarded 4,000 jobs last night" has to be answerable
  # afterwards.
  #
  # Each entry goes two ways. A line on the audit logger, which is the
  # application logger unless configured otherwise, so a trail exists without
  # anyone setting anything up; and an ActiveSupport::Notifications event, for
  # applications that keep their audit trail somewhere a log file cannot be:
  #
  #   ActiveSupport::Notifications.subscribe(SolidQueuePanel::Audit::EVENT) do |*, payload|
  #     AuditEntry.create!(payload)
  #   end
  #
  # The actor is whatever config.audit_actor returns. Without it the panel
  # records how the request was authenticated instead of who made it, which is
  # the honest answer when a single password is shared: a trail that cannot name
  # a person should say so rather than imply one.
  class Audit
    EVENT = "action.solid_queue_panel"

    class << self
      def record(action, actor:, ip:, **details)
        entry = { action: action.to_s, actor: actor, ip: ip, at: Time.current, **details }

        ActiveSupport::Notifications.instrument(EVENT, entry)
        write(entry)
        entry
      end

      private
        def write(entry)
          logger = SolidQueuePanel.configuration.audit_logger
          return unless logger

          logger.info { "[SolidQueuePanel] #{entry.except(:at).map { |key, value| "#{key}=#{value}" }.join(" ")}" }
        end
    end
  end
end
