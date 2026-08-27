# frozen_string_literal: true

module SolidQueuePanel
  class RecurringTasksController < ApplicationController
    RECENT_EXECUTIONS = 25

    def index
      @tasks = SolidQueue::RecurringTask.order(:key)
    end

    def show
      @task = SolidQueue::RecurringTask.find_by!(key: params[:key])
      @executions = @task.recurring_executions
        .includes(job: %i[ready_execution claimed_execution scheduled_execution blocked_execution failed_execution])
        .order(run_at: :desc)
        .limit(RECENT_EXECUTIONS)
    end
  end
end
