# frozen_string_literal: true

module SolidQueuePanel
  # The time window used by the dashboard chart and the metrics table. Periods
  # are expressed in hours so they survive a round trip through the query string.
  class TimePeriod
    BUCKETS = 24

    attr_reader :hours

    class << self
      def wrap(value)
        value.is_a?(self) ? value : new(value)
      end

      def all
        SolidQueuePanel.configuration.time_periods.map { |hours| new(hours) }
      end

      def default
        all.find { |period| period.hours == 24 } || all.first
      end
    end

    def initialize(hours)
      @hours = hours.to_i
      @hours = 24 unless @hours.positive?
    end

    def starts_at
      ends_at - duration
    end

    def ends_at
      @ends_at ||= Time.current
    end

    def range
      starts_at..ends_at
    end

    def duration
      hours.hours
    end

    def bucket_size
      duration / BUCKETS
    end

    def label
      ActiveSupport::Duration.build(duration.to_i).inspect
    end

    def ==(other)
      other.is_a?(self.class) && hours == other.hours
    end
    alias eql? ==

    def hash
      hours.hash
    end
  end
end
