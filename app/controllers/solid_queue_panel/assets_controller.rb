# frozen_string_literal: true

module SolidQueuePanel
  # Serves the dashboard's own CSS and JavaScript straight from the gem, so the
  # host application does not have to know about them: nothing to precompile, no
  # Sprockets or Propshaft configuration, and no CDN.
  #
  # It deliberately inherits from ActionController::Base rather than from the
  # engine's ApplicationController: assets carry no data and have to load even
  # when the dashboard itself redirects to a login page.
  class AssetsController < ActionController::Base
    # These are public, stateless files: CSRF has nothing to protect here, and
    # the same-origin check would refuse to serve the JavaScript to a <script>
    # tag.
    skip_forgery_protection

    ASSETS = {
      "solid_queue_panel.css" => { path: "app/assets/builds/solid_queue_panel.css", type: "text/css" },
      "solid_queue_panel.js" => { path: "app/assets/javascripts/solid_queue_panel/application.js", type: "text/javascript" }
    }.freeze

    def show
      asset = ASSETS[params[:file]]
      return head :not_found unless asset

      # Assets are addressed by gem version, so a build can be cached forever
      # and an upgrade busts the cache on its own.
      expires_in 1.year, public: true
      send_file Engine.root.join(asset[:path]), type: asset[:type], disposition: "inline"
    end
  end
end
