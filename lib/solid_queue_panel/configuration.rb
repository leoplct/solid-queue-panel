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

    # Custom authentication callable, instance_exec'd in the controller.
    attr_reader :authentication_block

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
    end

    # Runs an arbitrary authentication check before every request. The block is
    # instance-exec'd in the controller, so all its helpers are available.
    #
    #   config.authenticate_with { redirect_to("/login") unless current_user&.admin? }
    def authenticate_with(&block)
      @authentication_block = block
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
      def compare(given, expected)
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(given.to_s),
          Digest::SHA256.hexdigest(expected.to_s)
        )
      end
  end
end
