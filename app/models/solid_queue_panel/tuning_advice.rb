# frozen_string_literal: true

module SolidQueuePanel
  # Turns the numbers recorded for one machine into the two decisions you
  # actually have to make: how many worker processes to run, and how many
  # threads to give each of them.
  #
  # Every statement says what was measured before it says what to do, because
  # the right answer depends on whether your jobs wait on the network or burn
  # CPU, and only you know that.
  class TuningAdvice
    # Memory to leave to the rest of the machine: the web server, the database
    # client, the operating system.
    RESERVE_RATIO = 0.15
    MINIMUM_RESERVE_KB = 256 * 1024

    # Above this share of memory, adding anything is asking for the OOM killer.
    MEMORY_PRESSURE = 85

    # Load average per core above which the machine has no CPU left to give.
    SATURATED = 1.0
    IDLE = 0.5

    Statement = Struct.new(:level, :text)

    def initialize(host)
      @host = host
    end

    def statements
      @statements ||= [ memory_statement, cpu_statement, pool_statement, recommendation_statement ].compact
    end

    # How many worker processes the memory on this machine can hold, at the size
    # the workers currently are.
    def affordable_processes
      return unless worker_memory_kb&.positive? && usable_memory_kb

      [ usable_memory_kb / worker_memory_kb, 1 ].max
    end

    def suggested_processes
      return unless affordable_processes && host.cpu_count

      [ affordable_processes, host.cpu_count ].min
    end

    def suggested_threads
      return unless host.threads_per_worker

      if saturated? then [ host.threads_per_worker - 1, 1 ].max
      elsif idle? then host.threads_per_worker + 2
      else host.threads_per_worker
      end
    end

    private
      attr_reader :host

      def worker_memory_kb
        host.worker_memory_kb.positive? ? host.worker_memory_kb : nil
      end

      # Memory that could be spent on workers: what the machine has, minus what
      # is already used by everything else, minus a reserve.
      def usable_memory_kb
        return unless host.memory_kb && host.available_memory_kb

        reserve = [ host.memory_kb * RESERVE_RATIO, MINIMUM_RESERVE_KB ].max
        usable = host.available_memory_kb + (host.workers.size * worker_memory_kb.to_i) - reserve

        usable.positive? ? usable.to_i : 0
      end

      def saturated?
        host.load_per_core.to_f > SATURATED
      end

      def idle?
        host.load_per_core && host.load_per_core < IDLE
      end

      def memory_statement
        return unless worker_memory_kb && host.memory_kb

        measured = "Each worker holds #{megabytes(worker_memory_kb)}, and the machine is using " \
                   "#{percentage(host.memory_usage)} of its #{megabytes(host.memory_kb)}."

        if host.memory_usage.to_f >= MEMORY_PRESSURE
          Statement.new(:warning, "#{measured} There is no room left for another process: give the workers fewer threads, or move some to another machine.")
        elsif affordable_processes
          Statement.new(:info, "#{measured} There is room for about #{affordable_processes} worker #{"process".pluralize(affordable_processes)} of that size.")
        else
          Statement.new(:info, measured)
        end
      end

      def cpu_statement
        return unless host.load_per_core && host.cpu_count

        measured = "Load average is #{host.load_average.round(2)} on #{host.cpu_count} #{"core".pluralize(host.cpu_count)}, " \
                   "#{percentage(host.load_per_core * 100)} per core."

        if saturated?
          Statement.new(:warning, "#{measured} The CPU is the bottleneck: more threads will not make jobs finish sooner, and may make them slower.")
        elsif idle?
          Statement.new(:info, "#{measured} The CPU is mostly idle, so if jobs are piling up they are waiting on something else: more threads per worker will help if they wait on the network or the database.")
        else
          Statement.new(:info, "#{measured} The machine is comfortably busy.")
        end
      end

      # Solid Queue needs one database connection per working thread, plus one
      # for the process itself.
      def pool_statement
        return unless host.total_worker_threads && database_pool_size

        needed = host.threads_per_worker + 1

        if database_pool_size < needed
          Statement.new(:warning, "Each worker runs #{host.threads_per_worker} threads but the database pool is #{database_pool_size}: raise `pool` in config/database.yml to at least #{needed}, or threads will queue on connections.")
        end
      end

      def recommendation_statement
        return unless suggested_processes && suggested_threads

        current = "#{host.workers.size} #{"process".pluralize(host.workers.size)} × #{host.threads_per_worker} threads"
        suggestion = "#{suggested_processes} × #{suggested_threads}"

        return Statement.new(:success, "Running #{current}, which fits this machine.") if same_as_current?

        Statement.new(:info, "Running #{current}. A starting point to measure against: #{suggestion}.")
      end

      def same_as_current?
        suggested_processes == host.workers.size && suggested_threads == host.threads_per_worker
      end

      def database_pool_size
        @database_pool_size ||= begin
          db_config = SolidQueue::Record.connection_pool.db_config
          db_config.respond_to?(:max_connections) ? db_config.max_connections : db_config.pool
        rescue StandardError
          nil
        end
      end

      def megabytes(kilobytes)
        "#{ActiveSupport::NumberHelper.number_to_delimited((kilobytes / 1024.0).round)} MB"
      end

      def percentage(value)
        "#{value.to_f.round}%"
      end
  end
end
