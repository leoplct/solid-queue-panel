# frozen_string_literal: true

module SolidQueuePanel
  # The engine is intentionally tiny: it isolates its namespace and nothing
  # else. CSS and JavaScript are served by SolidQueuePanel::AssetsController
  # straight from the gem, so the dashboard behaves the same with Propshaft,
  # Sprockets or no asset pipeline at all, and the host application has nothing
  # to precompile.
  class Engine < ::Rails::Engine
    isolate_namespace SolidQueuePanel

    rake_tasks do
      load File.expand_path("../tasks/solid_queue_panel.rake", __dir__)
    end
  end
end
