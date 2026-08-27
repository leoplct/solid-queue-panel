# frozen_string_literal: true

module SolidQueuePanel
  class DashboardController < ApplicationController
    def index
      @registry = ProcessRegistry.new
      @health = Health.new(overview: overview, registry: @registry)
      @capacity = QueueCapacity.new
    end
  end
end
