# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"

ActiveRecord::Migration.verbose = false
load File.expand_path("dummy/db/queue_schema.rb", __dir__)

# The resource metrics tables come from the migration the gem generates, so the
# tests run against the very migration applications get. The test database is
# disposable, so it is rebuilt from scratch on every run.
ActiveRecord::Base.connection_pool.with_connection do |connection|
  %w[solid_queue_panel_process_samples solid_queue_panel_job_usages].each do |table|
    connection.drop_table(table, if_exists: true)
  end

  connection.execute("DELETE FROM schema_migrations") if connection.table_exists?("schema_migrations")
end

ActiveRecord::MigrationContext.new(File.expand_path("dummy/db/migrate", __dir__)).migrate

require_relative "support/job_factory"

module SolidQueuePanel
  # Runs a block as if the resource metrics tables had never been installed,
  # which is how the panel starts out in every application.
  module WithoutResourceMetrics
    METRICS_MODELS = [ JobUsage, ProcessSample ].freeze

    def without_resource_metrics
      SolidQueuePanel.singleton_class.alias_method :recorded_resource_metrics?, :resource_metrics?
      SolidQueuePanel.define_singleton_method(:resource_metrics?) { false }

      yield
    ensure
      SolidQueuePanel.singleton_class.alias_method :resource_metrics?, :recorded_resource_metrics?
      SolidQueuePanel.singleton_class.remove_method :recorded_resource_metrics?
    end

    # Stubbing the predicate is not the same as not having the tables: the
    # models still know their columns, so code that builds a scope before it
    # checks the predicate keeps working in the tests and blows up in an
    # application. This points the models at tables that really are not there.
    def without_resource_metrics_tables
      names = METRICS_MODELS.to_h { |model| [ model, model.table_name ] }

      names.each_key do |model|
        model.table_name = "#{names[model]}_not_installed"
        model.reset_column_information
      end

      # The installed check remembers its answer for a minute, and the answer
      # just changed.
      reset_resource_metrics_cache

      yield
    ensure
      names.each do |model, name|
        model.table_name = name
        model.reset_column_information
      end

      reset_resource_metrics_cache
    end

    private
      def reset_resource_metrics_cache
        SolidQueuePanel.instance_variable_set(:@resource_metrics, nil)
        SolidQueuePanel.instance_variable_set(:@resource_metrics_checked_at, nil)
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
