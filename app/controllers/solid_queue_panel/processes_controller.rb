# frozen_string_literal: true

module SolidQueuePanel
  class ProcessesController < ApplicationController
    before_action :ensure_write_access, only: :prune

    def index
      @registry = ProcessRegistry.new
    end

    def show
      @process = SolidQueue::Process.find(params[:id])
      @registry = ProcessRegistry.new
      @claimed_executions = @process.claimed_executions.includes(:job).order(created_at: :asc)
    end

    # Deregisters processes that stopped sending heartbeats and fails the jobs
    # they had claimed, exactly like the supervisor does on its own schedule.
    def prune
      SolidQueue::Process.prune
      audit :prune_processes
      redirect_to processes_path, notice: "Dead processes were pruned."
    end
  end
end
