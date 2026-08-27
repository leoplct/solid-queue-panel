# frozen_string_literal: true

module SolidQueuePanel
  # One reading of how much memory and CPU a Solid Queue process was using, and
  # of the machine (or container) it was running on. Written by the recorder
  # inside every Solid Queue process, a few times a minute.
  class ProcessSample < Record
    scope :in_period, ->(period) { where(created_at: period.range) }
    scope :on_host, ->(hostname) { where(hostname: hostname) }
    scope :workers, -> { where(kind: "Worker") }

    # The most recent sample of every process, which is what the panel shows as
    # the current state.
    def self.latest_per_process(within: 5.minutes)
      where(created_at: within.ago..)
        .order(:name, created_at: :desc)
        .to_a
        .uniq(&:name)
    end

    def self.prune(retention)
      where(created_at: ...retention.ago).delete_all
    end

    def rss_mb
      rss_kb.to_f / 1024
    end

    def memory_mb
      memory_kb&.fdiv(1024)
    end

    def available_memory_mb
      available_memory_kb&.fdiv(1024)
    end

    def used_memory_kb
      return unless memory_kb && available_memory_kb

      memory_kb - available_memory_kb
    end

    def memory_usage
      return unless used_memory_kb && memory_kb.to_i.positive?

      used_memory_kb.fdiv(memory_kb) * 100
    end

    def load_per_core
      return unless load_average && cpu_count.to_i.positive?

      load_average / cpu_count
    end
  end
end
