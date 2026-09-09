# frozen_string_literal: true

require "digest"

module SolidQueuePanel
  # Holds every knob the panel exposes. Defaults are meant to be safe for a
  # production mount: no destructive shortcuts beyond the ones Solid Queue
  # itself provides, and a polling interval that will not hammer the database.
  class Configuration
    # Name shown in the navigation bar, next to the Solid Queue logo.
    attr_accessor :application_name

    # Number of records per page in every paginated table.
    attr_accessor :page_size

    # Seconds between two live refreshes. Set to +0+ to disable polling.
    attr_accessor :polling_interval

    # When true, every destructive action (retry, discard, pause, clear...) is
    # hidden from the UI and refused by the controllers.
    attr_accessor :read_only

    # Periods (in hours) offered by the metrics and dashboard time filters.
    attr_accessor :time_periods

    # Controller the engine controllers inherit from, as a String so that it can
    # be resolved lazily. Use it to reuse the authentication and layout of the
    # host application, e.g. "Admin::BaseController".
    attr_accessor :base_controller_class

    # Credentials of the built-in sign in form. When both are set, the panel
    # asks for them before showing anything.
    attr_accessor :username, :password

    # How long a sign in lasts before the panel asks for the password again.
    attr_accessor :session_duration

    # Record memory and CPU usage from inside the Solid Queue processes. Needs
    # the tables added by `bin/rails generate solid_queue_panel:resource_metrics`;
    # without them nothing is recorded, whatever this is set to.
    attr_accessor :record_resource_metrics

    # Seconds between two resource samples, per process.
    attr_accessor :resource_sample_interval

    # How long samples and per job class usage are kept.
    attr_accessor :resource_retention

    # Keys whose values are replaced with [FILTERED] wherever the panel shows an
    # Active Job payload. Defaults to the application's own filter_parameters,
    # so the panel hides what the application already hides from its logs.
    # Set it to an empty array to show payloads exactly as they are stored.
    attr_writer :filter_parameters

    # Show no job arguments at all, anywhere. The strongest of the two, for
    # panels watching queues whose payloads nobody should read.
    attr_accessor :hide_job_arguments

    # Where the audit trail of every action that changes something is written.
    # Defaults to the application logger.
    attr_writer :audit_logger

    # Custom authentication callable, instance_exec'd in the controller.
    attr_reader :authentication_block

    # Names the person behind a request in the audit trail, instance_exec'd in
    # the controller.
    attr_reader :audit_actor_block

    DEFAULT_TIME_PERIODS = [ 1, 6, 24, 24 * 7 ].freeze
    private_constant :DEFAULT_TIME_PERIODS

    def initialize
      @application_name = nil
      @page_size = 25
      @polling_interval = 5
      @read_only = false
      @time_periods = DEFAULT_TIME_PERIODS.dup
      @base_controller_class = "ActionController::Base"
      @username = nil
      @password = nil
      @session_duration = 2.weeks
      @record_resource_metrics = true
      @resource_sample_interval = 30.seconds
      @resource_retention = 3.days
      @authentication_block = nil
      @filter_parameters = nil
      @hide_job_arguments = false
      @audit_logger = nil
      @audit_actor_block = nil
    end

    # Runs an arbitrary authentication check before every request. The block is
    # instance-exec'd in the controller, so all its helpers are available.
    #
    #   config.authenticate_with { redirect_to("/login") unless current_user&.admin? }
    def authenticate_with(&block)
      @authentication_block = block
    end

    # Names whoever is behind a request, for the audit trail. Without it the
    # panel can only record how the request was authenticated, which is the
    # honest answer when everybody shares one password.
    #
    #   config.audit_actor { current_user&.email }
    def audit_actor(&block)
      @audit_actor_block = block
    end

    # True once both a username and a password are configured, which is what
    # turns the built-in sign in on.
    def credentials?
      username.present? && password.present?
    end

    # Compared through their digests, and with a non short-circuiting AND, so
    # that neither the username nor the password can be guessed one character
    # at a time.
    def valid_credentials?(given_username, given_password)
      credentials? && (compare(given_username, username) & compare(given_password, password))
    end

    # Identifies the current credentials in the session cookie: changing the
    # password signs everybody out.
    def credentials_digest
      Digest::SHA256.hexdigest("solid_queue_panel:#{username}:#{password}")
    end

    # Nil means "whatever the application filters", which is almost always the
    # right answer: a key worth hiding from the logs is worth hiding here too.
    def filter_parameters
      @filter_parameters.nil? ? application_filter_parameters : @filter_parameters
    end

    def hide_job_arguments?
      !!hide_job_arguments
    end

    def audit_logger
      @audit_logger || Rails.logger
    end

    def record_resource_metrics?
      !!record_resource_metrics
    end

    def read_only?
      !!read_only
    end

    def polling?
      polling_interval.to_i.positive?
    end

    private
      def application_filter_parameters
        Rails.application.config.filter_parameters
      rescue StandardError
        []
      end

      def compare(given, expected)
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(given.to_s),
          Digest::SHA256.hexdigest(expected.to_s)
        )
      end
  end
end
