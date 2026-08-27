# frozen_string_literal: true

module SolidQueuePanel
  # Everything the panel knows about this installation, as plain text: the
  # configuration, the processes that are running, the state of every queue, the
  # resources they use and the files they were configured from.
  #
  # It exists to be pasted somewhere else — into an LLM that is helping you tune
  # the queue, into an issue, into a message to a colleague — so it is written
  # to be read without the panel next to it, and it never includes credentials.
  class SettingsReport
    def initialize(settings: Settings.new, registry: ProcessRegistry.new, capacity: QueueCapacity.new,
                   health: Health.new, resources: ResourceReport.new)
      @settings = settings
      @registry = registry
      @capacity = capacity
      @health = health
      @resources = resources
    end

    def to_s
      sections.compact_blank.join("\n\n") + "\n"
    end

    private
      attr_reader :settings, :registry, :capacity, :health, :resources

      def sections
        [
          heading,
          versions,
          alerts,
          solid_queue_settings,
          panel_settings,
          database,
          configured_processes,
          registered_processes,
          queues,
          machines,
          heaviest_jobs,
          config_file(settings.queue_config_file),
          config_file(settings.recurring_config_file)
        ]
      end

      def heading
        [
          "# Solid Queue report",
          "Generated at #{Time.current.utc.iso8601} by Solid Queue Panel #{SolidQueuePanel::VERSION}.",
          "Times are UTC. Durations are in seconds unless they say otherwise."
        ].join("\n")
      end

      def versions
        section "Versions", settings.versions.map { |setting| "#{setting.name}: #{setting.value}" }
      end

      def alerts
        return if health.alerts.none?

        section "What the panel is complaining about", health.alerts.map { |alert| "#{alert.level}: #{alert.message}" }
      end

      def solid_queue_settings
        section "Solid Queue configuration", settings.solid_queue_settings.map { |setting|
          "#{setting.name}: #{describe(setting.value)}"
        }
      end

      # The panel's own configuration, credentials left out on purpose.
      def panel_settings
        configuration = SolidQueuePanel.configuration

        section "Panel configuration", [
          "read_only: #{configuration.read_only?}",
          "polling_interval: #{configuration.polling_interval}",
          "page_size: #{configuration.page_size}",
          "resource_metrics_installed: #{SolidQueuePanel.resource_metrics?}",
          "record_resource_metrics: #{configuration.record_resource_metrics?}",
          "resource_sample_interval: #{describe(configuration.resource_sample_interval)}",
          "resource_retention: #{describe(configuration.resource_retention)}"
        ]
      end

      def database
        section "Queue database", settings.database.map { |setting| "#{setting.name}: #{setting.value}" }
      end

      def configured_processes
        processes = settings.configured_processes
        return section("Configured processes", [ "could not be read from the configuration file" ]) if processes.nil?

        lines = processes.group_by(&:kind).map do |kind, group|
          "#{kind} x #{group.size}: #{group.first.attributes.map { |key, value| "#{key}=#{describe(value)}" }.join(", ")}"
        end

        section "Configured processes (what Solid Queue starts)", lines
      end

      def registered_processes
        return section("Registered processes", [ "none: no Solid Queue process is running" ]) if registry.processes.none?

        lines = registry.processes.map do |process|
          [
            process.name,
            process.kind,
            "host=#{process.hostname}",
            "pid=#{process.pid}",
            ("queues=#{process.metadata["queues"]}" if process.metadata["queues"]),
            ("threads=#{process.metadata["thread_pool_size"]}" if process.metadata["thread_pool_size"]),
            ("polling=#{process.metadata["polling_interval"]}s" if process.metadata["polling_interval"]),
            ("busy=#{registry.busy_count(process)}" if process.kind == "Worker"),
            "heartbeat=#{seconds_ago(process.last_heartbeat_at)}s ago",
            ("NO HEARTBEAT" unless registry.alive?(process))
          ].compact.join("  ")
        end

        section "Registered processes (#{registry.total_threads} worker threads, #{registry.busy_threads} busy)", lines
      end

      def queues
        return section("Queues", [ "none" ]) if capacity.rows.none?

        lines = capacity.rows.map do |row|
          [
            "#{row.name}#{" (paused)" if row.paused?}",
            "capacity=#{row.capacity}",
            "in_progress=#{row.in_progress}",
            "pending=#{row.pending}",
            "blocked=#{row.blocked}",
            "scheduled=#{row.scheduled}",
            "retries=#{row.retries}",
            "dead=#{row.dead}",
            "finished_24h=#{row.finished}",
            "last_added=#{row.last_enqueued_at ? "#{seconds_ago(row.last_enqueued_at)}s ago" : "never"}",
            "eta=#{row.eta_seconds ? "#{row.eta_seconds.round}s#{"+" if row.partial_eta?}" : "unknown"}"
          ].join("  ")
        end

        section "Queues", lines
      end

      def machines
        return unless resources.any?

        resources.hosts.flat_map do |host|
          section "Machine #{host.hostname}", [
            "cores=#{host.cpu_count}  memory=#{megabytes(host.memory_kb)}  used=#{percentage(host.memory_usage)}  " \
              "load=#{host.load_average}  load_per_core=#{percentage(host.load_per_core.to_f * 100)}",
            "solid_queue_memory=#{megabytes(host.solid_queue_memory_kb)}  per_worker=#{megabytes(host.worker_memory_kb)}  " \
              "workers=#{host.workers.size}  threads_per_worker=#{host.threads_per_worker}",
            "advice:",
            *host.advice.statements.map { |statement| "  - #{statement.text}" },
            *suggestion(host)
          ]
        end.join("\n\n")
      end

      def suggestion(host)
        return [] unless host.advice.suggested_processes && host.advice.suggested_threads

        [ "  suggested starting point: #{host.advice.suggested_processes} processes x #{host.advice.suggested_threads} threads" ]
      end

      def heaviest_jobs
        return unless resources.job_usage?

        lines = resources.heaviest_jobs.map do |usage|
          "#{usage.class_name}  runs=#{usage.executions}  failures=#{usage.failures}  " \
            "cpu_total=#{(usage.cpu_ms / 1000.0).round(1)}s  cpu_avg=#{(usage.average_cpu_ms / 1000.0).round(2)}s  " \
            "duration_avg=#{(usage.average_wall_ms / 1000.0).round(2)}s  memory_avg=#{megabytes(usage.average_memory_growth_kb)}  " \
            "peak_process_memory=#{megabytes(usage.max_rss_kb)}"
        end

        section "Heaviest job classes (last #{resources.period.label})", lines
      end

      def config_file(file)
        return section("#{file.relative_path}", [ "not found" ]) unless file.exist?

        "## #{file.relative_path}\n\n```yaml\n#{file.contents.strip}\n```"
      end

      def section(title, lines)
        return if lines.blank?

        "## #{title}\n\n#{lines.join("\n")}"
      end

      def describe(value)
        case value
        when nil then "not set"
        when ActiveSupport::Duration then "#{value.inspect} (#{value.to_i}s)"
        when Hash then value.map { |key, nested| "#{key}=#{describe(nested)}" }.join(" ")
        when Array then value.map { |item| describe(item) }.join(",")
        else value.to_s
        end
      end

      def megabytes(kilobytes)
        kilobytes ? "#{(kilobytes / 1024.0).round}MB" : "unknown"
      end

      def percentage(value)
        value ? "#{value.round}%" : "unknown"
      end

      def seconds_ago(time)
        (Time.current - time).round
      end
  end
end
