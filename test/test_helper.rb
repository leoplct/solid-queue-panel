# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"

ActiveRecord::Migration.verbose = false
load File.expand_path("dummy/db/queue_schema.rb", __dir__)

require_relative "support/job_factory"

module SolidQueuePanel
  class TestCase < ActiveSupport::TestCase
    include JobFactory

    setup { reset_solid_queue }
    teardown { SolidQueuePanel.configuration.read_only = false }
  end

  class IntegrationTestCase < ActionDispatch::IntegrationTest
    include JobFactory

    setup { reset_solid_queue }

    teardown do
      SolidQueuePanel.configuration.read_only = false
      SolidQueuePanel.configuration.username = nil
      SolidQueuePanel.configuration.password = nil
    end

    private
      def panel
        SolidQueuePanel::Engine.routes.url_helpers
      end
  end
end
