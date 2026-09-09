# frozen_string_literal: true

module SolidQueuePanel
  # Gives every controller one way to write down what it just did. See
  # SolidQueuePanel::Audit for where the entries go.
  module Auditing
    extend ActiveSupport::Concern

    private
      def audit(action, **details)
        Audit.record(action, actor: audit_actor, ip: request.remote_ip, **details)
      end

      # Whoever the application says is behind the request, and failing that a
      # description of how the request got in. The panel never invents an
      # identity it does not have.
      def audit_actor
        from_application = instance_exec(&panel_configuration.audit_actor_block) if panel_configuration.audit_actor_block

        from_application.presence || authentication_description
      rescue StandardError
        authentication_description
      end

      def authentication_description
        if panel_configuration.credentials? then "shared credentials"
        elsif panel_configuration.authentication_block then "application authentication"
        else "unauthenticated"
        end
      end
  end
end
