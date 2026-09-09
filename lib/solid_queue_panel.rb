# frozen_string_literal: true

require "solid_queue"

require "solid_queue_panel/version"
require "solid_queue_panel/configuration"
require "solid_queue_panel/engine"

# Solid Queue Panel is a mountable Rails engine that gives Solid Queue the
# kind of web UI Sidekiq users are used to: an overview of the whole system,
# live process and queue monitoring, job browsing, per class metrics and the
# resources every worker is using.
module SolidQueuePanel
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias config configuration

    # True once the resource metrics tables exist. Both are checked: they come
    # from a single migration, but a half applied one leaves the panel querying
    # a table that is not there. While they are missing the check is repeated at
    # most once a minute, so installing them does not need a restart of the
    # application.
    def resource_metrics?
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if @resource_metrics_checked_at.nil? || (!@resource_metrics && now - @resource_metrics_checked_at > 60)
        @resource_metrics = table_installed?
        @resource_metrics_checked_at = now
      end

      @resource_metrics
    end

    # Configures the panel, typically from an initializer.
    #
    #   SolidQueuePanel.configure do |config|
    #     config.application_name = "Acme"
    #     config.read_only = Rails.env.production?
    #   end
    def configure
      yield configuration
    end

    private
      def table_installed?
        ProcessSample.table_exists? && JobUsage.table_exists?
      rescue StandardError
        false
      end
  end
end
