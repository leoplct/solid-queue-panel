# frozen_string_literal: true

module SolidQueuePanel
  class SettingsController < ApplicationController
    def show
      @settings = Settings.new
      @registry = ProcessRegistry.new
    end
  end
end
