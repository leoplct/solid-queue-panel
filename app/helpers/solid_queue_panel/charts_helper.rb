# frozen_string_literal: true

module SolidQueuePanel
  # Draws the dashboard chart as plain inline SVG: no chart library, no inline
  # styles, and tooltips that work without JavaScript.
  module ChartsHelper
    WIDTH = 1200
    HEIGHT = 260
    PADDING = { top: 12, right: 10, bottom: 26, left: 46 }.freeze
    GRID_LINES = 4
    X_LABELS = 6

    def throughput_chart(throughput)
      points = throughput.points
      return chart_placeholder if points.size < 2

      scale = chart_scale(throughput.peak)

      tag.svg(
        safe_join([
          chart_grid_lines(scale),
          chart_x_labels(throughput),
          chart_area(points, scale),
          chart_line(points, scale, :finished, "stroke-emerald-500"),
          chart_line(points, scale, :enqueued, "stroke-indigo-500"),
          chart_line(points, scale, :failed, "stroke-rose-500"),
          chart_hotspots(points)
        ]),
        viewBox: "0 0 #{WIDTH} #{HEIGHT}",
        class: "h-auto w-full",
        role: "img",
        "aria-label": "Jobs enqueued, finished and failed over the last #{throughput.period.label}"
      )
    end

    # A horizontal bar split by job state, the way RabbitMQ shows ready and
    # unacknowledged messages side by side: the shape of a queue's backlog at
    # a glance.
    def backlog_bar(segments, total:, width: 160, height: 8)
      total = [ total.to_i, 1 ].max
      offset = 0

      bars = segments.filter_map do |label, value, css_class|
        next if value.to_i.zero?

        bar_width = width * value / total.to_f
        bar = tag.rect(tag.title("#{number_with_delimiter(value)} #{label}"),
                       x: offset.round(2), y: 0, width: bar_width.round(2), height: height, rx: 2, class: css_class)
        offset += bar_width
        bar
      end

      tag.svg(safe_join(bars), viewBox: "0 0 #{width} #{height}", width: width, height: height,
              class: "overflow-visible", role: "img", "aria-hidden": true)
    end

    # A compact area chart for one measurement over time, the kind that sits
    # inside a card next to the current value. Gaps in the data are simply not
    # plotted.
    def metric_chart(points, stroke: "stroke-emerald-500", fill: "fill-emerald-500/15", height: 56)
      data = points.reject { |_time, value| value.nil? }
      return tag.div("No data yet", class: "flex h-14 items-center text-xs text-slate-400") if data.size < 2

      width = 300
      times = data.map { |time, _value| time.to_i }
      span = [ times.max - times.min, 1 ].max
      ceiling = [ data.map(&:last).max, 0.001 ].max

      coordinates = data.map do |time, value|
        x = ((time.to_i - times.min) / span.to_f * width).round(2)
        y = (height - (value / ceiling * (height - 4))).round(2)

        "#{x},#{y}"
      end

      tag.svg(
        safe_join([
          tag.polygon(points: ([ "0,#{height}" ] + coordinates + [ "#{width},#{height}" ]).join(" "), class: fill),
          tag.polyline(points: coordinates.join(" "), class: "#{stroke} fill-none", "stroke-width": 1.5, "stroke-linejoin": "round")
        ]),
        viewBox: "0 0 #{width} #{height}",
        class: "h-14 w-full",
        preserveAspectRatio: "none",
        "aria-hidden": true
      )
    end

    # A wider gauge with the numbers written inside it, for the capacity table:
    # green while there is room, amber when it is getting full, red when every
    # thread is taken.
    def utilization_bar(value, max, width: 132, height: 22)
      max = max.to_i
      ratio = max.positive? ? value.to_f / max : 0
      filled = max.positive? ? (width * [ ratio, 1.0 ].min) : 0

      color = case ratio
      when 0...0.7 then "fill-emerald-500"
      when 0.7...0.95 then "fill-amber-500"
      else "fill-rose-500"
      end

      tag.svg(
        safe_join([
          tag.rect(x: 0, y: 0, width: width, height: height, rx: 5, class: "fill-slate-200 dark:fill-slate-700"),
          tag.rect(x: 0, y: 0, width: filled.round(2), height: height, rx: 5, class: max.positive? ? color : "fill-transparent"),
          tag.text(max.positive? ? "#{value} / #{max}" : "no worker",
                   x: width / 2, y: height / 2 + 4, "text-anchor": "middle",
                   class: "fill-slate-900 text-[11px] font-medium dark:fill-slate-900")
        ]),
        viewBox: "0 0 #{width} #{height}", width: width, height: height, role: "img",
        "aria-label": "#{value} of #{max} threads busy"
      )
    end

    # A capacity gauge: busy threads against the pool size, RabbitMQ's
    # resource bars in miniature.
    def meter_bar(value, max, width: 90, height: 6)
      max = [ max.to_i, 1 ].max
      filled = (width * value.to_i / max.to_f).clamp(0, width)
      color = case value.to_f / max
      when 0...0.7 then "fill-emerald-500"
      when 0.7...0.95 then "fill-amber-500"
      else "fill-rose-500"
      end

      tag.svg(
        safe_join([
          tag.rect(x: 0, y: 0, width: width, height: height, rx: 3, class: "fill-slate-200 dark:fill-slate-700"),
          tag.rect(x: 0, y: 0, width: filled.round(2), height: height, rx: 3, class: color)
        ]),
        viewBox: "0 0 #{width} #{height}", width: width, height: height, role: "img",
        "aria-label": "#{value} of #{max}"
      )
    end

    private
      def chart_placeholder
        tag.div("Nothing has run in this period yet", class: "flex h-40 items-center justify-center text-sm text-slate-500")
      end

      # Rounds the top of the scale up to the next 1, 2 or 5 so the grid labels
      # are numbers a human would have picked.
      def chart_scale(peak)
        peak = peak.to_i
        return 1 if peak <= 1

        magnitude = 10**Math.log10(peak).floor
        [ 1, 2, 5, 10 ].map { |factor| factor * magnitude }.find { |candidate| candidate >= peak } || peak
      end

      def chart_grid_lines(scale)
        safe_join((0..GRID_LINES).flat_map do |step|
          y = PADDING[:top] + (plot_height * step / GRID_LINES.to_f)
          value = (scale * (GRID_LINES - step) / GRID_LINES.to_f).round

          [
            tag.line(x1: PADDING[:left], y1: y, x2: WIDTH - PADDING[:right], y2: y, class: "stroke-slate-200 dark:stroke-slate-800", "stroke-width": 1),
            tag.text(number_with_delimiter(value), x: PADDING[:left] - 8, y: y + 4, "text-anchor": "end", class: "fill-slate-400 text-[10px]")
          ]
        end)
      end

      def chart_x_labels(throughput)
        points = throughput.points
        step = [ (points.size / X_LABELS.to_f).ceil, 1 ].max
        format = throughput.period.hours > 48 ? "%d %b" : "%H:%M"

        safe_join(points.each_with_index.filter_map do |point, index|
          next unless (index % step).zero?

          tag.text(point.time.in_time_zone.strftime(format), x: chart_x(index, points.size), y: HEIGHT - 8, "text-anchor": "middle", class: "fill-slate-400 text-[10px]")
        end)
      end

      def chart_area(points, scale)
        bottom = PADDING[:top] + plot_height
        coordinates = chart_coordinates(points, scale, :finished)

        tag.polygon(points: ([ "#{PADDING[:left]},#{bottom}" ] + coordinates + [ "#{WIDTH - PADDING[:right]},#{bottom}" ]).join(" "), class: "fill-emerald-500/15")
      end

      def chart_line(points, scale, series, css_class)
        tag.polyline(
          points: chart_coordinates(points, scale, series).join(" "),
          class: "#{css_class} fill-none",
          "stroke-width": 2,
          "stroke-linejoin": "round",
          "stroke-linecap": "round"
        )
      end

      # Transparent columns with a native tooltip: hovering a bucket tells you
      # exactly what happened in it, with no JavaScript involved.
      def chart_hotspots(points)
        width = plot_width / points.size.to_f

        safe_join(points.each_with_index.map do |point, index|
          tooltip = [
            point.time.in_time_zone.strftime("%d %b %H:%M"),
            "#{number_with_delimiter(point.enqueued)} enqueued",
            "#{number_with_delimiter(point.finished)} finished",
            "#{number_with_delimiter(point.failed)} failed"
          ].join(" · ")

          tag.rect(
            tag.title(tooltip),
            x: PADDING[:left] + (index * width),
            y: PADDING[:top],
            width: width,
            height: plot_height,
            class: "fill-transparent hover:fill-slate-500/10"
          )
        end)
      end

      def chart_coordinates(points, scale, series)
        points.each_with_index.map { |point, index| "#{chart_x(index, points.size)},#{chart_y(point.public_send(series), scale)}" }
      end

      def chart_x(index, size)
        (PADDING[:left] + (plot_width * index / (size - 1).to_f)).round(2)
      end

      def chart_y(value, scale)
        (PADDING[:top] + plot_height - (plot_height * value / scale.to_f)).round(2)
      end

      def plot_width
        WIDTH - PADDING[:left] - PADDING[:right]
      end

      def plot_height
        HEIGHT - PADDING[:top] - PADDING[:bottom]
      end
  end
end
