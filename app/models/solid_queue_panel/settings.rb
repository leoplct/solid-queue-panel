# frozen_string_literal: true

require "yaml"

module SolidQueuePanel
  # Read-only view of how Solid Queue is configured in this application: the
  # runtime settings, the processes described in config/queue.yml, the recurring
  # schedule, and where the queue data actually lives.
  class Settings
    Setting = Struct.new(:name, :value, :description)
    ConfigFile = Struct.new(:path, :contents) do
      def exist?
        contents.present?
      end

      def relative_path
        path.to_s.delete_prefix("#{Rails.root}/")
      end
    end

    # Every setting Solid Queue exposes, with the reason you would touch it.
    # Order matches the order they are documented in the Solid Queue README.
    SOLID_QUEUE_SETTINGS = [
      [ :preserve_finished_jobs, "Keep finished jobs in solid_queue_jobs instead of deleting them right away." ],
      [ :clear_finished_jobs_after, "How long finished jobs are kept before the dispatcher prunes them." ],
      [ :default_concurrency_control_period, "Default duration of concurrency locks when a job does not set one." ],
      [ :process_heartbeat_interval, "How often each process updates its heartbeat." ],
      [ :process_alive_threshold, "A process with no heartbeat for this long is considered dead and pruned." ],
      [ :shutdown_timeout, "Grace period given to in-flight jobs when a process is asked to stop." ],
      [ :silence_polling, "Skip logging the queries the pollers run every few milliseconds." ],
      [ :use_skip_locked, "Use SELECT ... FOR UPDATE SKIP LOCKED when claiming jobs." ],
      [ :connects_to, "Database Solid Queue models connect to, when it is not the primary one." ],
      [ :supervisor_pidfile, "Pidfile written by the supervisor process." ]
    ].freeze

    def solid_queue_settings
      SOLID_QUEUE_SETTINGS.filter_map do |name, description|
        Setting.new(name.to_s, SolidQueue.public_send(name), description) if SolidQueue.respond_to?(name)
      end
    end

    def panel_settings
      [
        Setting.new("application_name", configuration.application_name, "Name shown in the navigation bar."),
        Setting.new("read_only", configuration.read_only?, "Hide and refuse every destructive action."),
        Setting.new("polling_interval", configuration.polling_interval, "Seconds between two live refreshes, 0 to disable."),
        Setting.new("page_size", configuration.page_size, "Rows per page in every table."),
        Setting.new("base_controller_class", configuration.base_controller_class, "Controller the dashboard inherits from."),
        Setting.new("authentication", authentication_description, "How access to this dashboard is protected.")
      ]
    end

    # Processes Solid Queue would start with the current configuration, defaults
    # included. Nil when the configuration cannot be read, e.g. because the
    # config file has a syntax error.
    def configured_processes
      @configured_processes ||= SolidQueue::Configuration.new.configured_processes
    rescue StandardError
      nil
    end

    def queue_config_file
      @queue_config_file ||= read_config_file(ENV.fetch("SOLID_QUEUE_CONFIG", "config/queue.yml"))
    end

    def recurring_config_file
      @recurring_config_file ||= read_config_file(ENV.fetch("SOLID_QUEUE_RECURRING_SCHEDULE", "config/recurring.yml"))
    end

    def database
      @database ||= SolidQueue::Record.connection_pool.db_config.then do |db_config|
        [
          Setting.new("adapter", db_config.adapter, nil),
          Setting.new("database", db_config.database, nil),
          Setting.new("connection pool size", connection_pool_size(db_config), nil),
          Setting.new("configuration name", db_config.name, nil)
        ]
      end
    end

    def versions
      [
        Setting.new("solid_queue_panel", SolidQueuePanel::VERSION, nil),
        Setting.new("solid_queue", SolidQueue::VERSION, nil),
        Setting.new("rails", Rails.version, nil),
        Setting.new("ruby", RUBY_VERSION, nil),
        Setting.new("active_job adapter", active_job_adapter, nil)
      ]
    end

    def active_job_adapter
      ActiveJob::Base.queue_adapter_name
    rescue StandardError
      nil
    end

    private
      # Renamed in Rails 8.1, still the old name on 7.2 and 8.0.
      def connection_pool_size(db_config)
        db_config.respond_to?(:max_connections) ? db_config.max_connections : db_config.pool
      end

      def authentication_description
        if configuration.credentials? then "sign in form"
        elsif configuration.authentication_block then "custom block"
        else "none: protect the mount point in your routes"
        end
      end

      def configuration
        SolidQueuePanel.configuration
      end

      def read_config_file(relative_path)
        path = Rails.root.join(relative_path)
        ConfigFile.new(path, (path.read if path.exist?))
      end
  end
end
