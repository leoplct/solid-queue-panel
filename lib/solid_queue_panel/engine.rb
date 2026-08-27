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

    # Resource metrics are collected inside the Solid Queue processes, so the
    # panel hooks into their lifecycle. The hooks are cheap to register: nothing
    # runs until a Solid Queue process actually boots, and nothing is recorded
    # until the tables are installed.
    config.after_initialize do
      next unless SolidQueuePanel.configuration.record_resource_metrics?

      SolidQueue.on_start { SolidQueuePanel::Recorder.start(kind: "Supervisor") }
      SolidQueue.on_stop { SolidQueuePanel::Recorder.stop }

      %w[worker dispatcher scheduler].each do |process|
        SolidQueue.public_send(:"on_#{process}_start") { SolidQueuePanel::Recorder.start(kind: process.capitalize) }
        SolidQueue.public_send(:"on_#{process}_stop") { SolidQueuePanel::Recorder.stop }
      end
    end
  end
end
