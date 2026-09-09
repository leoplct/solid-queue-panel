# frozen_string_literal: true

module SolidQueuePanel
  # Job payloads are the one place where the panel shows data the application
  # owns rather than data Solid Queue generated: whatever was handed to
  # perform_later ends up here, and some of it is not for whoever is watching
  # the queue.
  #
  # Filtering is by key, exactly like the filtering Rails already applies to its
  # own logs, and reuses the application's filter_parameters by default: a key
  # worth hiding from the log is worth hiding here. A hash argument of
  # {"email" => "..."} is therefore redacted, while a bare positional "..." is
  # not, since nothing in the payload says what it is. Panels watching queues
  # whose payloads nobody should read want hide_job_arguments, which shows none
  # of it whatever the keys are called.
  class PayloadFilter
    HIDDEN = "[HIDDEN]"

    # Arrays cannot be handed to ActiveSupport::ParameterFilter directly, so
    # positional arguments travel under a key on their way through it.
    WRAPPER = "arguments"

    def initialize(filters = SolidQueuePanel.configuration.filter_parameters,
                   hidden: SolidQueuePanel.configuration.hide_job_arguments?)
      @filters = Array(filters)
      @hidden = hidden
    end

    def hidden?
      @hidden
    end

    # The whole Active Job payload, as shown on a job page.
    def payload(arguments)
      return HIDDEN if hidden?

      filter(arguments)
    end

    # Just the positional arguments, as shown in a list row. Nil rather than a
    # placeholder: the row simply leaves the arguments out.
    def arguments(list)
      return if hidden?

      filter(list)
    end

    private
      def filter(value)
        case value
        when Hash then parameter_filter.filter(value)
        when Array then parameter_filter.filter(WRAPPER => value)[WRAPPER]
        else value
        end
      end

      def parameter_filter
        @parameter_filter ||= ActiveSupport::ParameterFilter.new(@filters)
      end
  end
end
