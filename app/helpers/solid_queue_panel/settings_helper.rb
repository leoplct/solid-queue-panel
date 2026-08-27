# frozen_string_literal: true

module SolidQueuePanel
  module SettingsHelper
    # Configuration values are a mix of durations, booleans, arrays and hashes.
    # This renders each of them the way you would have written it in an
    # initializer.
    def setting_value(value)
      case value
      when nil then "—"
      when ActiveSupport::Duration then value.inspect
      when Array then value.map { |item| setting_value(item) }.join(", ")
      when Hash then value.map { |key, nested| "#{key}: #{setting_value(nested)}" }.join(" · ")
      when SolidQueue::RecurringTask then value.key
      else value.to_s
      end
    end

    def configured_process_settings(process)
      process.attributes.map { |key, value| "#{key}: #{setting_value(value)}" }.join(" · ")
    end
  end
end
