# frozen_string_literal: true

module SolidQueuePanel
  # Per job class statistics over a time window: how many jobs ran, how many
  # failed and how long they took from enqueue to completion.
  #
  # Solid Queue does not record when a job started running, so durations are
  # measured from +created_at+ to +finished_at+ and therefore include the time
  # the job spent waiting in its queue. Durations are averaged over a bounded
  # sample of the most recent jobs to keep the page cheap on busy installations.
  class Metrics
    SAMPLE_SIZE = 5_000
    SORTS = %w[total_duration average_duration finished failed class_name].freeze

    Row = Struct.new(:class_name, :enqueued, :finished, :failed, :in_progress, :average_duration, :total_duration, :sampled) do
      def executions
        finished + failed
      end

      def failure_rate
        return 0.0 if executions.zero?

        (failed.to_f / executions * 100).round(1)
      end

      def sample_size
      SAMPLE_SIZE
    end

    def sampled?
        sampled
      end
    end

    attr_reader :period, :sort

    def initialize(period: TimePeriod.default, sort: nil)
      @period = TimePeriod.wrap(period)
      @sort = SORTS.include?(sort.to_s) ? sort.to_s : "total_duration"
    end

    def rows
      @rows ||= sorted(class_names.map { |class_name| build_row(class_name) })
    end

    def any?
      rows.any?
    end

    def finished_jobs_preserved?
      SolidQueue.preserve_finished_jobs?
    end

    def sample_size
      SAMPLE_SIZE
    end

    def sampled?
      durations_sample.size >= SAMPLE_SIZE
    end

    private
      def build_row(class_name)
        durations = durations_by_class.fetch(class_name, [])

        Row.new(
          class_name,
          enqueued_counts.fetch(class_name, 0),
          finished_counts.fetch(class_name, 0),
          failed_counts.fetch(class_name, 0),
          in_progress_counts.fetch(class_name, 0),
          durations.any? ? durations.sum / durations.size : nil,
          durations.sum,
          durations.any?
        )
      end

      def class_names
        @class_names ||= (enqueued_counts.keys + finished_counts.keys + failed_counts.keys + in_progress_counts.keys).uniq
      end

      def sorted(rows)
        case sort
        when "class_name" then rows.sort_by(&:class_name)
        when "finished" then rows.sort_by { |row| -row.finished }
        when "failed" then rows.sort_by { |row| [ -row.failed, -row.finished ] }
        when "average_duration" then rows.sort_by { |row| -(row.average_duration || 0) }
        else rows.sort_by { |row| [ -(row.total_duration || 0), -row.finished ] }
        end
      end

      def enqueued_counts
        @enqueued_counts ||= SolidQueue::Job.where(created_at: period.range).group(:class_name).count
      end

      def finished_counts
        @finished_counts ||= SolidQueue::Job.where(finished_at: period.range).group(:class_name).count
      end

      def failed_counts
        @failed_counts ||= SolidQueue::Job.joins(:failed_execution)
          .where(solid_queue_failed_executions: { created_at: period.range })
          .group(:class_name).count
      end

      def in_progress_counts
        @in_progress_counts ||= SolidQueue::Job.joins(:claimed_execution).group(:class_name).count
      end

      def durations_by_class
        @durations_by_class ||= durations_sample.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(class_name, created_at, finished_at), durations|
          durations[class_name] << (finished_at - created_at) if created_at && finished_at
        end
      end

      def durations_sample
        @durations_sample ||= SolidQueue::Job.where(finished_at: period.range)
          .order(finished_at: :desc)
          .limit(SAMPLE_SIZE)
          .pluck(:class_name, :created_at, :finished_at)
      end
  end
end
