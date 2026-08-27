# frozen_string_literal: true

require "solid_queue"

require "solid_queue_panel/version"
require "solid_queue_panel/configuration"
require "solid_queue_panel/engine"

# Solid Queue Panel is a mountable Rails engine that gives Solid Queue the
# kind of web UI Sidekiq users are used to: an overview of the whole system,
# live process and queue monitoring, job browsing and per-class metrics.
module SolidQueuePanel
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias config configuration

    # Configures the dashboard, typically from an initializer.
    #
    #   SolidQueuePanel.configure do |config|
    #     config.application_name = "Acme"
    #     config.read_only = Rails.env.production?
    #   end
    def configure
      yield configuration
    end
  end
end
