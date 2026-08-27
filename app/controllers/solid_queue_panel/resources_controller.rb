# frozen_string_literal: true

module SolidQueuePanel
  class ResourcesController < ApplicationController
    def show
      @period = time_period
      @report = ResourceReport.new(period: @period)
    end
  end
end
