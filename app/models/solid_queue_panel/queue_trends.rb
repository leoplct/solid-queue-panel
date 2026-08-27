# frozen_string_literal: true

module SolidQueuePanel
  # The shape of the last day of every queue: how much work arrived and how much
  # was finished, hour by hour. Two grouped queries cover every queue at once,
  # and both of them are the kind Solid Queue has an index for.
  #
  # Work "arrives" when a job becomes due rather than when the row was written,
  # which is the same instant for a job enqueued for now and the right instant
  # for one enqueued for later.
  class QueueTrends
    Point = Struct.new(:time, :enqueued, :finished) do
      def peak
        [ enqueued, finished ].max
      end
    end

    attr_reader :period

    def initialize(period: TimePeriod.default)
      @period = TimePeriod.wrap(period)
    end

    def for(queue_name)
      points.fetch(queue_name) { empty_points }
    end

    def enqueued(queue_name)
      self.for(queue_name).sum(&:enqueued)
    end

    def finished(queue_name)
      self.for(queue_name).sum(&:finished)
    end

    def any?(queue_name)
      self.for(queue_name).any? { |point| point.peak.positive? }
    end

    private
      def points
        @points ||= queue_names.index_with do |queue_name|
          indexes.map do |index|
            Point.new(
              bucket.time_for(index),
              enqueued_counts.fetch([ queue_name, index ], 0),
              finished_counts.fetch([ queue_name, index ], 0)
            )
          end
        end
      end

      def empty_points
        @empty_points ||= indexes.map { |index| Point.new(bucket.time_for(index), 0, 0) }
      end

      def queue_names
        @queue_names ||= (enqueued_counts.keys + finished_counts.keys).map(&:first).uniq
      end

      def enqueued_counts
        @enqueued_counts ||= bucket.count_by(SolidQueue::Job.where(scheduled_at: period.range), :scheduled_at, :queue_name)
      end

      def finished_counts
        @finished_counts ||= bucket.count_by(SolidQueue::Job.where(finished_at: period.range), :finished_at, :queue_name)
      end

      def bucket
        @bucket ||= TimeBucket.new(period.bucket_size)
      end

      def indexes
        @indexes ||= (bucket.index_for(period.starts_at)..bucket.index_for(period.ends_at)).to_a
      end
  end
end
