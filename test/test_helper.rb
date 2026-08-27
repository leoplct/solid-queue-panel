# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"

ActiveRecord::Migration.verbose = false
load File.expand_path("dummy/db/queue_schema.rb", __dir__)

# The resource metrics tables come from the migration the gem generates, so the
# tests run against the very migration applications get.
ActiveRecord::MigrationContext.new(File.expand_path("dummy/db/migrate", __dir__)).migrate

require_relative "support/job_factory"

module SolidQueuePanel
  # Runs a block as if the resource metrics tables had never been installed,
  # which is how the panel starts out in every application.
  module WithoutResourceMetrics
    def without_resource_metrics
      SolidQueuePanel.singleton_class.alias_method :recorded_resource_metrics?, :resource_metrics?
      SolidQueuePanel.define_singleton_method(:resource_metrics?) { false }

      yield
    ensure
      SolidQueuePanel.singleton_class.alias_method :resource_metrics?, :recorded_resource_metrics?
      SolidQueuePanel.singleton_class.remove_method :recorded_resource_metrics?
    end
  end

  class TestCase < ActiveSupport::TestCase
    include JobFactory
    include WithoutResourceMetrics

    setup { reset_solid_queue }
    teardown { SolidQueuePanel.configuration.read_only = false }
  end

  class IntegrationTestCase < ActionDispatch::IntegrationTest
    include JobFactory
    include WithoutResourceMetrics

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
