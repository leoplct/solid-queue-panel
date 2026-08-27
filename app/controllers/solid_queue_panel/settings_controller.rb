# frozen_string_literal: true

module SolidQueuePanel
  class SettingsController < ApplicationController
    def show
      @settings = Settings.new
      @registry = ProcessRegistry.new
    end

    # Everything on this page as plain text, ready to be pasted into an LLM or
    # an issue. Built on demand: the page itself refreshes every few seconds and
    # has no business gathering all of this every time.
    def report
      render plain: SettingsReport.new.to_s
    end
  end
end
