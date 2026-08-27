# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module SolidQueuePanel
  module Generators
    # Creates the two tables the panel needs to record how much memory and CPU
    # the Solid Queue processes use. They live next to the Solid Queue tables,
    # so the migration goes to the migrations path of whatever database Solid
    # Queue is configured to use.
    class ResourceMetricsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Adds the tables that record process memory, CPU and per job class resource usage."

      def create_migration_file
        migration_template "create_resource_metrics.rb.tt",
                           File.join(migrations_path, "create_solid_queue_panel_resource_metrics.rb")
      end

      def explain
        say ""
        say "Run bin/rails db:migrate to create the tables, then restart your Solid Queue", :green
        say "processes so they start recording."
        say ""
      end

      private
        # The queue database has its own migrations path when the application
        # keeps Solid Queue in a separate database.
        def migrations_path
          paths = SolidQueuePanel::Record.connection_pool.db_config.migrations_paths

          Array(paths).first || "db/migrate"
        rescue StandardError
          "db/migrate"
        end

        def migration_version
          "[#{ActiveRecord::Migration.current_version}]"
        end
    end
  end
end
