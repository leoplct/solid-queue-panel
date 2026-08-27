# frozen_string_literal: true

module SolidQueuePanel
  class MetricsController < ApplicationController
    def show
      @period = time_period
      @metrics = Metrics.new(period: @period, sort: params[:sort])
    end
  end
end
