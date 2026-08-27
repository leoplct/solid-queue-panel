# frozen_string_literal: true

module SolidQueuePanel
  # The built-in sign in form. It is only reachable when a username and a
  # password are configured; otherwise access is controlled elsewhere and there
  # is nothing to sign in to.
  class SessionsController < ApplicationController
    allow_unauthenticated_access only: %i[new create]

    layout "solid_queue_panel/plain"

    # Rails 7.2 and later can throttle an action out of the box. It quietly does
    # nothing when the application has no cache store, which is fine: this is a
    # second line of defence, not the only one.
    if respond_to?(:rate_limit)
      rate_limit to: 10, within: 3.minutes, only: :create,
                 with: -> { redirect_to login_path, alert: "Too many attempts. Try again in a few minutes." }
    end

    def new
      redirect_to root_path unless sign_in_required?
    end

    def create
      if panel_configuration.valid_credentials?(params[:username], params[:password])
        sign_in
        redirect_to return_path, notice: "Welcome back."
      else
        flash.now[:alert] = "Wrong username or password."
        render :new, status: 401
      end
    end

    def destroy
      sign_out
      redirect_to login_path, notice: "Signed out."
    end

    private
      # Only ever redirect back into the panel itself: a return path coming from
      # the query string is not to be trusted. Note that root_path here is the
      # path the engine is mounted at.
      def return_path
        candidate = params[:return_to].to_s

        if candidate.start_with?(root_path) && !candidate.start_with?("//")
          candidate
        else
          root_path
        end
      end
  end
end
