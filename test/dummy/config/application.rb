# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

require "solid_queue"
require "solid_queue_panel"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.0

    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = "solid_queue_panel_dummy_secret_key_base"
    config.active_job.queue_adapter = :solid_queue
    config.logger = ActiveSupport::Logger.new(File.expand_path("../log/dummy.log", __dir__))

    # What config/initializers/filter_parameter_logging.rb sets in a generated
    # application. The panel reuses it, so the dummy has to have it.
    config.filter_parameters += %i[passw email secret token _key crypt salt certificate otp ssn cvv cvc]
    config.hosts.clear
  end
end
