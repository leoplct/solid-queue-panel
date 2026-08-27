# frozen_string_literal: true

module SolidQueuePanel
  module ApplicationHelper
    NavItem = Struct.new(:name, :label, :path, :icon)

    def panel_name
      panel_configuration.application_name.presence || "Solid Queue"
    end

    def page_title(title = nil)
      [ title, panel_name ].compact.join(" · ")
    end

    def navigation_items
      [
        NavItem.new("dashboard", "Dashboard", root_path, "squares-2x2"),
        NavItem.new("processes", "Processes", processes_path, "cpu-chip"),
        NavItem.new("queues", "Queues", queues_path, "queue-list"),
        NavItem.new("jobs", "Jobs", jobs_path, "rectangle-stack"),
        NavItem.new("recurring_tasks", "Recurring", recurring_tasks_path, "arrow-path"),
        NavItem.new("metrics", "Metrics", metrics_path, "chart-pie"),
        NavItem.new("resources", "Resources", resources_path, "server-stack"),
        NavItem.new("settings", "Settings", settings_path, "cog-6-tooth")
      ]
    end

    def current_nav?(item)
      controller_name == item.name
    end

    def panel_stylesheet_url
      panel_asset_url_for("solid_queue_panel.css")
    end

    def panel_javascript_url
      panel_asset_url_for("solid_queue_panel.js")
    end

    def panel_asset_url_for(file)
      panel_asset_path(digest: AssetsController.digest(file), file: file)
    end

    # Number formatting is used on every page and every stat: keep it short.
    def number(value)
      number_with_delimiter(value.to_i)
    end

    # Rates read better in the unit that gives a number a human can hold on to:
    # jobs per second when things are busy, per minute or per hour when not.
    def megabytes(kilobytes)
      return tag.span("—", class: "text-slate-400") if kilobytes.nil?

      "#{number_with_delimiter((kilobytes / 1024.0).round)} MB"
    end

    def percentage(value, precision: 0)
      return tag.span("—", class: "text-slate-400") if value.nil?

      "#{number_with_precision(value, precision: precision)}%"
    end

    def rate_in_words(per_second)
      case per_second
      when 1.0.. then "#{number_with_precision(per_second, precision: 1)}/s"
      when (1.0 / 60).. then "#{number_with_precision(per_second * 60, precision: 1)}/min"
      else "#{number_with_precision(per_second * 3600, precision: 1)}/h"
      end
    end

    def relative_time(time)
      return tag.span("—", class: "text-slate-400") if time.blank?

      tag.time(distance_in_words(time), datetime: time.utc.iso8601, title: absolute_time(time), class: "cursor-help")
    end

    def absolute_time(time)
      return "—" if time.blank?

      time.in_time_zone.strftime("%d %b %Y %H:%M:%S %Z")
    end

    def distance_in_words(time)
      seconds = (Time.current - time).to_i

      seconds.negative? ? "in #{duration_in_words(seconds.abs)}" : "#{duration_in_words(seconds)} ago"
    end

    # Durations show up everywhere: latency, job runtimes, polling intervals.
    # Two units are enough to be precise without being noisy.
    def duration_in_words(seconds)
      seconds = seconds.to_f

      case seconds
      when 0...1 then "#{(seconds * 1000).round}ms"
      when 1...60 then "#{seconds.round}s"
      when 60...3600 then "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
      when 3600...86_400 then "#{(seconds / 3600).floor}h #{(seconds % 3600 / 60).floor}m"
      else "#{(seconds / 86_400).floor}d #{(seconds % 86_400 / 3600).floor}h"
      end
    end

    def badge(text, color: "slate", icon_name: nil)
      classes = class_names(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
        badge_color_classes(color)
      )

      tag.span(safe_join([ (icon(icon_name, css_class: "size-3.5") if icon_name), text ].compact), class: classes)
    end

    def badge_color_classes(color)
      {
        "emerald" => "bg-emerald-50 text-emerald-700 ring-emerald-600/20 dark:bg-emerald-500/10 dark:text-emerald-300 dark:ring-emerald-500/30",
        "rose" => "bg-rose-50 text-rose-700 ring-rose-600/20 dark:bg-rose-500/10 dark:text-rose-300 dark:ring-rose-500/30",
        "amber" => "bg-amber-50 text-amber-800 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-300 dark:ring-amber-500/30",
        "blue" => "bg-blue-50 text-blue-700 ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-300 dark:ring-blue-500/30",
        "indigo" => "bg-indigo-50 text-indigo-700 ring-indigo-600/20 dark:bg-indigo-500/10 dark:text-indigo-300 dark:ring-indigo-500/30",
        "violet" => "bg-violet-50 text-violet-700 ring-violet-600/20 dark:bg-violet-500/10 dark:text-violet-300 dark:ring-violet-500/30",
        "slate" => "bg-slate-100 text-slate-700 ring-slate-500/20 dark:bg-slate-500/10 dark:text-slate-300 dark:ring-slate-400/20"
      }.fetch(color.to_s, "bg-slate-100 text-slate-700 ring-slate-500/20 dark:bg-slate-500/10 dark:text-slate-300 dark:ring-slate-400/20")
    end

    # Builds a URL for the current page with a few query parameters replaced,
    # which is all filters, sorting and pagination need.
    def url_with(**overrides)
      url_for(request.query_parameters.symbolize_keys.merge(overrides).compact_blank)
    end

    def flash_classes(level)
      case level.to_s
      when "alert", "error" then "bg-rose-50 text-rose-800 ring-rose-600/20 dark:bg-rose-500/10 dark:text-rose-200 dark:ring-rose-500/30"
      else "bg-emerald-50 text-emerald-800 ring-emerald-600/20 dark:bg-emerald-500/10 dark:text-emerald-200 dark:ring-emerald-500/30"
      end
    end

    def alert_classes(level)
      case level.to_s
      when "error" then "bg-rose-50 text-rose-800 ring-rose-600/20 dark:bg-rose-500/10 dark:text-rose-200 dark:ring-rose-500/30"
      when "warning" then "bg-amber-50 text-amber-900 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-200 dark:ring-amber-500/30"
      else "bg-blue-50 text-blue-800 ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-500/30"
      end
    end

    def alert_icon(level)
      case level.to_s
      when "error" then "exclamation-circle"
      when "warning" then "exclamation-triangle"
      else "information-circle"
      end
    end

    def time_periods
      TimePeriod.all
    end

    def theme_options
      [ [ "system", "computer-desktop", "System" ], [ "light", "sun", "Light" ], [ "dark", "moon", "Dark" ] ]
    end

    def button_classes(variant = :secondary)
      base = "inline-flex items-center justify-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition disabled:opacity-50"

      case variant.to_sym
      when :primary
        "#{base} bg-slate-900 text-white hover:bg-slate-700 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-200"
      when :danger
        "#{base} text-rose-700 ring-1 ring-inset ring-rose-300 hover:bg-rose-50 dark:text-rose-300 dark:ring-rose-500/40 dark:hover:bg-rose-500/10"
      else
        "#{base} text-slate-700 ring-1 ring-inset ring-slate-300 hover:bg-slate-50 dark:text-slate-200 dark:ring-slate-700 dark:hover:bg-slate-800"
      end
    end

    def card_classes
      "rounded-xl bg-white shadow-sm ring-1 ring-slate-200 dark:bg-slate-900 dark:ring-slate-800"
    end

    def card_header_classes
      "flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-4 py-3 dark:border-slate-800"
    end

    def table_header_classes
      "px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400"
    end

    def table_cell_classes
      "px-4 py-2.5 text-sm text-slate-700 dark:text-slate-300"
    end
  end
end
