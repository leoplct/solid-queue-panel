# frozen_string_literal: true

module SolidQueuePanel
  # How long a job of each class takes to run, which is what turns a number of
  # pending jobs into an estimate of when the queue will be empty.
  #
  # The recorder measures the real execution time of every job, so that is used
  # when it is installed. Without it the panel falls back to the only thing
  # Solid Queue stores, the time between enqueue and completion, which includes
  # the wait in the queue and therefore reads long.
  class JobDurations
    WINDOW = 24.hours
    SAMPLE_SIZE = 2_000
    DEFAULT_SECONDS = 1.0

    def average_seconds(class_name)
      averages.fetch(class_name) { overall_average }
    end

    def overall_average
      @overall_average ||= averages.values.sum / averages.size.to_f if averages.any?
      @overall_average || DEFAULT_SECONDS
    end

    def measured?
      source == :measured
    end

    def known?
      averages.any?
    end

    def source
      averages
      @source
    end

    private
      def averages
        @averages ||= begin
          measured = measured_averages

          if measured.any?
            @source = :measured
            measured
          else
            @source = estimated_averages.any? ? :estimated : :unknown
            estimated_averages
          end
        end
      end

      # Execution time as measured inside the workers.
      def measured_averages
        return {} unless SolidQueuePanel.resource_metrics?

        JobUsage.where(bucket_at: WINDOW.ago..)
          .group(:class_name)
          .pluck(:class_name, Arel.sql("SUM(wall_ms)"), Arel.sql("SUM(executions)"))
          .to_h { |class_name, wall_ms, executions| [ class_name, executions.to_i.positive? ? wall_ms.to_f / executions / 1000 : nil ] }
          .compact
      rescue StandardError
        {}
      end

      # Enqueue to completion of the most recent finished jobs, computed in Ruby
      # so it works the same on every database.
      def estimated_averages
        @estimated_averages ||= SolidQueue::Job.where(finished_at: WINDOW.ago..)
          .order(finished_at: :desc)
          .limit(SAMPLE_SIZE)
          .pluck(:class_name, :created_at, :finished_at)
          .group_by(&:first)
          .transform_values do |rows|
            durations = rows.filter_map { |_class_name, created_at, finished_at| finished_at - created_at if created_at && finished_at }
            durations.sum / durations.size if durations.any?
          end
          .compact
      end
  end
end
