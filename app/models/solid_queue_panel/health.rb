# frozen_string_literal: true

module SolidQueuePanel
  # The handful of checks worth surfacing at the top of the dashboard: things
  # that are silently wrong and would otherwise only show up as jobs that never
  # run.
  class Health
    Alert = Struct.new(:level, :message)

    def initialize(overview: Overview.new, registry: ProcessRegistry.new)
      @overview = overview
      @registry = registry
    end

    def alerts
      @alerts ||= [
        no_processes_alert,
        dead_processes_alert,
        no_supervisor_alert,
        paused_queues_alert,
        adapter_alert
      ].compact
    end

    def any?
      alerts.any?
    end

    private
      attr_reader :overview, :registry

      def no_processes_alert
        return if registry.any?

        Alert.new(:error, "No Solid Queue process is registered: jobs are being enqueued but nothing is working on them.")
      end

      def dead_processes_alert
        return if registry.dead.none?

        Alert.new(:warning, "#{pluralize(registry.dead.size, "process")} stopped sending heartbeats and will be pruned.")
      end

      def no_supervisor_alert
        return unless registry.any?
        return if registry.processes.any? { |process| process.kind == "Supervisor" }

        Alert.new(:warning, "No supervisor is registered: dead processes and orphaned jobs will not be cleaned up.")
      end

      def paused_queues_alert
        return if overview.paused_queues.zero?

        Alert.new(:warning, "#{pluralize(overview.paused_queues, "queue")} paused: jobs are piling up in them.")
      end

      def adapter_alert
        adapter = ActiveJob::Base.queue_adapter_name
        return if adapter.to_s == "solid_queue"

        Alert.new(:info, "Active Job is using the #{adapter} adapter, so new jobs are not enqueued into Solid Queue.")
      rescue StandardError
        nil
      end

      def pluralize(count, noun)
        ActionController::Base.helpers.pluralize(count, noun)
      end
  end
end
