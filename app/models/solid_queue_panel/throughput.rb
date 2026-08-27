# frozen_string_literal: true

module SolidQueuePanel
  # Jobs enqueued, finished and failed over time, bucketed for the dashboard
  # chart. Charting arrivals next to completions is what turns the chart into an
  # answer: as long as the enqueued line stays under the finished one, the
  # workers are keeping up.
  class Throughput
    Point = Struct.new(:time, :enqueued, :finished, :failed) do
      def peak
        [ enqueued, finished + failed ].max
      end
    end

    attr_reader :period

    def initialize(period: TimePeriod.default)
      @period = TimePeriod.wrap(period)
    end

    def points
      @points ||= indexes.map do |index|
        Point.new(
          bucket.time_for(index),
          enqueued_counts.fetch(index, 0),
          finished_counts.fetch(index, 0),
          failed_counts.fetch(index, 0)
        )
      end
    end

    def enqueued
      @enqueued ||= points.sum(&:enqueued)
    end

    def finished
      @finished ||= points.sum(&:finished)
    end

    def failed
      @failed ||= points.sum(&:failed)
    end

    def peak
      @peak ||= points.map(&:peak).max.to_i
    end

    # Jobs per second, the way RabbitMQ reads its message rates: the number that
    # tells you whether the queue is draining or filling up.
    def enqueued_rate
      rate(enqueued)
    end

    def completion_rate
      rate(finished + failed)
    end

    def falling_behind?
      enqueued_rate > completion_rate * 1.05
    end

    def any?
      peak.positive?
    end

    def failure_rate
      total = finished + failed
      return 0.0 if total.zero?

      (failed.to_f / total * 100).round(1)
    end

    def bucket_size
      bucket.size
    end

    private
      def rate(count)
        count / period.duration.to_f
      end

      def bucket
        @bucket ||= TimeBucket.new(period.bucket_size)
      end

      def indexes
        @indexes ||= (bucket.index_for(period.starts_at)..bucket.index_for(period.ends_at)).to_a
      end

      def enqueued_counts
        @enqueued_counts ||= bucket.count(SolidQueue::Job.where(created_at: period.range), :created_at)
      end

      def finished_counts
        @finished_counts ||= bucket.count(SolidQueue::Job.where(finished_at: period.range), :finished_at)
      end

      def failed_counts
        @failed_counts ||= bucket.count(SolidQueue::FailedExecution.where(created_at: period.range), :created_at)
      end
  end
end
