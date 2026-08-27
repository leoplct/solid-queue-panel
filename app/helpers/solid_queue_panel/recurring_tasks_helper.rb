# frozen_string_literal: true

module SolidQueuePanel
  module RecurringTasksHelper
    # Schedules are parsed by Fugit and can be invalid, for instance after a
    # typo in config/recurring.yml. The dashboard shows what it can instead of
    # blowing up.
    def recurring_next_time(task)
      task.next_time
    rescue StandardError
      nil
    end

    def recurring_target(task)
      if task.class_name.present?
        [ task.class_name, recurring_arguments(task) ].compact.join
      else
        task.command
      end
    end

    def recurring_arguments(task)
      arguments = Array(task.arguments)
      return if arguments.empty?

      "(#{arguments.map(&:inspect).join(", ")})"
    rescue StandardError
      nil
    end
  end
end
