# frozen_string_literal: true

module SolidQueuePanel
  # The panel can pause queues and discard jobs, so it always asks who you are,
  # in one of three ways:
  #
  # 1. a username and a password configured on SolidQueuePanel.configuration,
  #    which enable the built-in sign in form (and are accepted as HTTP basic
  #    credentials too, for scripts and monitoring);
  # 2. an authenticate_with block, when the host application already knows who
  #    its administrators are;
  # 3. nothing at all, for panels mounted behind an authenticated route
  #    constraint.
  module Authentication
    extend ActiveSupport::Concern

    SESSION_COOKIE = :solid_queue_panel_session

    included do
      before_action :authenticate_panel_access
      helper_method :sign_in_required?
    end

    class_methods do
      def allow_unauthenticated_access(**options)
        skip_before_action :authenticate_panel_access, **options
      end
    end

    private
      def authenticate_panel_access
        run_custom_authentication
        require_sign_in if sign_in_required? && !performed?
      end

      def run_custom_authentication
        instance_exec(&panel_configuration.authentication_block) if panel_configuration.authentication_block
      end

      def sign_in_required?
        panel_configuration.credentials?
      end

      def require_sign_in
        return if signed_in?

        if request.get? && !request.xhr?
          redirect_to login_path(return_to: request.fullpath)
        else
          head :unauthorized
        end
      end

      def signed_in?
        signed_in_through_session? || signed_in_through_http_basic?
      end

      def signed_in_through_session?
        cookies.signed[SESSION_COOKIE] == panel_configuration.credentials_digest
      end

      def signed_in_through_http_basic?
        authenticate_with_http_basic do |username, password|
          panel_configuration.valid_credentials?(username, password)
        end
      end

      def sign_in
        cookies.signed[SESSION_COOKIE] = {
          value: panel_configuration.credentials_digest,
          expires: panel_configuration.session_duration.from_now,
          httponly: true,
          same_site: :lax,
          secure: request.ssl?
        }
      end

      def sign_out
        cookies.delete(SESSION_COOKIE)
      end
  end
end
