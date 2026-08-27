# frozen_string_literal: true

module SolidQueuePanel
  class JobsController < ApplicationController
    before_action :ensure_write_access, only: %i[destroy retry dispatch_now bulk duplicates remove_duplicates run_all]
    before_action :set_job, only: %i[show destroy retry dispatch_now]

    def index
      @query = JobsQuery.new(**query_params)
      @pagination = paginate(@query.count)
      @jobs = @query.page(@pagination)
    end

    def show
      @failed_execution = @job.failed_execution
    end

    # Puts a failed job back in its queue, resetting the Active Job execution
    # counters so retries start from scratch.
    def retry
      if @job.retry
        redirect_back_with notice: "Job ##{@job.id} was enqueued again."
      else
        redirect_back_with alert: "Job ##{@job.id} has not failed, there is nothing to retry."
      end
    end

    # Moves a scheduled job's due date to now. The dispatcher picks it up on its
    # next poll, which keeps the job going through the usual concurrency checks.
    def dispatch_now
      if (execution = @job.scheduled_execution)
        SolidQueue::Job.transaction do
          execution.update!(scheduled_at: Time.current)
          @job.update!(scheduled_at: Time.current)
        end

        redirect_back_with notice: "Job ##{@job.id} is due now and will be dispatched shortly."
      else
        redirect_back_with alert: "Job ##{@job.id} is not scheduled."
      end
    end

    def destroy
      discard(@job)
      redirect_to jobs_path(query_params), notice: "Job ##{@job.id} was discarded."
    rescue SolidQueue::Execution::UndiscardableError => error
      redirect_back_with alert: error.message
    end

    def bulk
      jobs = SolidQueue::Job.where(id: Array(params[:job_ids]))

      case params[:bulk_action]
      when "retry" then redirect_to jobs_path(query_params), notice: retried_notice(jobs)
      when "discard" then redirect_to jobs_path(query_params), notice: discarded_notice(jobs)
      else redirect_to jobs_path(query_params), alert: "Unknown bulk action."
      end
    end

    # Puts every job of the current list back to work: failed jobs are enqueued
    # again, scheduled ones become due now, blocked ones are offered their
    # concurrency lock again.
    def run_all
      result = RunAllJobs.new(JobsQuery.new(**query_params)).run

      redirect_to jobs_path(query_params), notice: run_all_notice(result)
    end

    # Counts the copies waiting in a queue and shows what would go, so that
    # discarding them is a decision rather than a surprise. The scan only runs
    # when this page is asked for, never while browsing.
    def duplicates
      @queue_name = params[:queue_name]
      @preview = DuplicateJobs.new(queue_name: @queue_name).preview
    end

    # Discards the jobs waiting in a queue that are an exact copy of an earlier
    # one. See SolidQueuePanel::DuplicateJobs for what counts as a copy.
    def remove_duplicates
      result = DuplicateJobs.new(queue_name: params[:queue_name]).discard_all

      redirect_to jobs_path(status: "queued", queue_name: params[:queue_name].presence),
                  notice: duplicates_notice(result)
    end

    private
      def run_all_notice(result)
        notice = case result.status
        when "failed" then "#{helpers.pluralize(result.count, "failed job")} enqueued again."
        when "scheduled" then "#{helpers.pluralize(result.count, "scheduled job")} #{result.count == 1 ? "is" : "are"} due now, and will be dispatched on the next poll."
        when "blocked" then blocked_notice(result)
        else "Nothing to run."
        end

        result.capped? ? "#{notice} Only the first #{helpers.number_with_delimiter(RunAllJobs::MAX)} were taken: run it again for the rest." : notice
      end

      def blocked_notice(result)
        return "No blocked job could take its concurrency lock: they are all still waiting." unless result.any?

        notice = "#{helpers.pluralize(result.count, "blocked job")} released."
        return notice if result.left_behind.zero?

        "#{notice} #{helpers.pluralize(result.left_behind, "job")} still waiting on their concurrency limit."
      end

      def duplicates_notice(result)
        scanned = "#{helpers.pluralize(result.scanned, "queued job")} scanned"
        scanned += " (the scan stops at #{helpers.number_with_delimiter(DuplicateJobs::MAX_SCAN)})" if result.capped?

        if result.any?
          "Discarded #{helpers.pluralize(result.discarded, "duplicate job")}: #{scanned}."
        else
          "No exact duplicate found: #{scanned}."
        end
      end

      def set_job
        @job = SolidQueue::Job.find(params[:id])
      end

      def query_params
        params.permit(:status, :queue_name, :search).to_h.symbolize_keys
      end

      def retried_notice(jobs)
        retryable = jobs.joins(:failed_execution)
        count = retryable.count
        SolidQueue::FailedExecution.retry_all(retryable) if count.positive?

        "#{helpers.pluralize(count, "job")} enqueued again."
      end

      def discarded_notice(jobs)
        count = jobs.to_a.count { |job| discard_ignoring_running(job) }

        "#{helpers.pluralize(count, "job")} discarded."
      end

      def discard_ignoring_running(job)
        discard(job)
        true
      rescue SolidQueue::Execution::UndiscardableError
        false
      end

      # Finished jobs have no execution left to discard, so the job row itself
      # is what gets deleted.
      def discard(job)
        job.finished? ? job.destroy : job.discard
      end
  end
end
