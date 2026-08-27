# frozen_string_literal: true

require "digest"

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

    class << self
      # Assets are addressed by the digest of their contents, so a build can be
      # cached forever and still never go stale: upgrading the gem, or patching
      # it in place, changes the URL on its own. The digest is only recomputed
      # when the file changes.
      def digest(file)
        path = path_for(file)
        key = [ file, path.mtime.to_i ]

        digests[key] ||= Digest::MD5.file(path).hexdigest[0, 12]
      end

      def path_for(file)
        Engine.root.join(ASSETS.fetch(file)[:path])
      end

      private
        def digests
          @digests ||= {}
        end
    end

    def show
      return head :not_found unless ASSETS.key?(params[:file])

      expires_in 1.year, public: true
      send_file self.class.path_for(params[:file]), type: ASSETS[params[:file]][:type], disposition: "inline"
    end
  end
end
