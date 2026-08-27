# frozen_string_literal: true

module SolidQueuePanel
  # Stores the colour scheme in a cookie so the server can render the right
  # theme on the first paint, with no flash and no inline script.
  class ThemesController < ApplicationController
    THEMES = %w[light dark system].freeze

    def update
      theme = params[:theme].presence_in(THEMES) || "system"

      if theme == "system"
        cookies.delete(:solid_queue_panel_theme)
      else
        cookies[:solid_queue_panel_theme] = { value: theme, expires: 1.year.from_now, same_site: :lax }
      end

      redirect_back fallback_location: root_path
    end
  end
end
