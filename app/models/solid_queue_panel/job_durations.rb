# frozen_string_literal: true

module SolidQueuePanel
  # How long a job takes, which is what turns a number of pending jobs into an
  # estimate of when they will be done.
  #
  # The best answer is the same job with the same arguments: SyncJob(10) and
  # SyncJob(2_000) are the same class and rarely the same amount of work. When
  # there is no history for those arguments the class as a whole is used, and
  # when there is no history at all the answer is nil, which the panel shows as
  # unknown rather than as a guess.
  #
  # Durations measured inside the workers come from the resource metrics. Without
  # them the panel falls back to the only thing Solid Queue stores, the time
  # between enqueue and completion, which includes the wait in the queue.
  class JobDurations
    WINDOW = 24.hours
    SAMPLE_SIZE = 2_000

    Estimate = Struct.new(:seconds, :scope, :basis, :runs) do
      def by_arguments?
        scope == :arguments
      end

      def measured?
        basis == :measured
      end

      def to_s
        "#{seconds.round(1)}s"
      end
    end

    # The most specific estimate available for this job, or nil.
    def for_job(job)
      by_arguments(job) || for_class(class_name_of(job))
    end

    def for_class(class_name)
      measured_class_estimates[class_name] || observed_class_estimates[class_name]
    end

    def average_seconds(class_name)
      for_class(class_name)&.seconds
    end

    def known?
      measured_class_estimates.any? || observed_class_estimates.any?
    end

    # Where the class level estimates come from, which is what the panel tells
    # the reader so they know how much to trust them.
    def basis
      return :measured if measured_class_estimates.any?
      return :estimated if observed_class_estimates.any?

      :unknown
    end

    private
      def by_arguments(job)
        fingerprint = ArgumentsFingerprint.for(job)
        return if fingerprint.blank?

        argument_estimates[[ class_name_of(job), fingerprint ]]
      end

      def class_name_of(job)
        job.respond_to?(:class_name) ? job.class_name : job.class.name
      end

      # Execution time per set of arguments, as measured inside the workers.
      def argument_estimates
        @argument_estimates ||= usage_estimates(JobUsage.by_arguments, scope: :arguments) do |class_name, fingerprint|
          [ class_name, fingerprint ]
        end
      end

      def measured_class_estimates
        @measured_class_estimates ||= usage_estimates(JobUsage.totals, scope: :class) { |class_name, _| class_name }
      end

      def usage_estimates(relation, scope:)
        return {} unless SolidQueuePanel.resource_metrics?

        relation.where(bucket_at: WINDOW.ago..)
          .group(:class_name, :arguments_fingerprint)
          .pluck(:class_name, :arguments_fingerprint, Arel.sql("SUM(wall_ms)"), Arel.sql("SUM(executions)"))
          .each_with_object({}) do |(class_name, fingerprint, wall_ms, executions), estimates|
            next unless executions.to_i.positive?

            estimates[yield(class_name, fingerprint)] =
              Estimate.new(wall_ms.to_f / executions / 1000, scope, :measured, executions.to_i)
          end
      rescue StandardError
        {}
      end

      # Enqueue to completion of the most recent finished jobs, computed in Ruby
      # so it works the same on every database.
      def observed_class_estimates
        @observed_class_estimates ||= SolidQueue::Job.where(finished_at: WINDOW.ago..)
          .order(finished_at: :desc)
          .limit(SAMPLE_SIZE)
          .pluck(:class_name, :created_at, :finished_at)
          .group_by(&:first)
          .each_with_object({}) do |(class_name, rows), estimates|
            durations = rows.filter_map { |_name, created_at, finished_at| finished_at - created_at if created_at && finished_at }
            next if durations.empty?

            estimates[class_name] = Estimate.new(durations.sum / durations.size, :class, :estimated, durations.size)
          end
      end
  end
end
