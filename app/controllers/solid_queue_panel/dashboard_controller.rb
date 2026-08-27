# frozen_string_literal: true

module SolidQueuePanel
  class DashboardController < ApplicationController
    RECENT_FAILURES = 5

    def index
      @registry = ProcessRegistry.new
      @health = Health.new(overview: overview, registry: @registry)
      @capacity = QueueCapacity.new
      @recent_failures = recent_failures
    end

    private
      def recent_failures
        SolidQueue::Job.joins(:failed_execution)
          .order(SolidQueue::FailedExecution.arel_table[:created_at].desc)
          .limit(RECENT_FAILURES)
          .preload(:failed_execution)
      end
  end
end
