# frozen_string_literal: true

module SolidQueuePanel
  class ApplicationController < SolidQueuePanel.configuration.base_controller_class.constantize
    include Authentication

    layout "solid_queue_panel/application"

    helper_method :overview, :panel_configuration, :read_only?, :current_theme, :polling_interval

    private
      def overview
        @overview ||= Overview.new
      end

      def panel_configuration
        SolidQueuePanel.configuration
      end

      def read_only?
        panel_configuration.read_only?
      end

      def polling_interval
        panel_configuration.polling_interval.to_i
      end

      def current_theme
        cookies[:solid_queue_panel_theme].presence_in(%w[light dark])
      end

      def paginate(count)
        Pagination.new(page: params[:page], per_page: panel_configuration.page_size, total_count: count)
      end

      def time_period
        TimePeriod.wrap(params[:period].presence || TimePeriod.default.hours)
      end

      # Guards every action that writes. Destructive controls are also hidden
      # from the UI in read-only mode, this is the server-side half of that.
      def ensure_write_access
        return unless read_only?

        redirect_back fallback_location: root_path, alert: "The panel is running in read-only mode."
      end

      def redirect_back_with(notice: nil, alert: nil)
        redirect_back fallback_location: root_path, notice: notice, alert: alert
      end
  end
end
