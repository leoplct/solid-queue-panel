# frozen_string_literal: true

require "digest"

module SolidQueuePanel
  # Identifies a job by the arguments it was enqueued with, so that runs of
  # SyncJob.perform_later(10) can be told apart from runs of
  # SyncJob.perform_later(2_000) when estimating how long the next one will take.
  #
  # Only the arguments count: everything else in the Active Job payload is about
  # this particular enqueue, not about the work.
  class ArgumentsFingerprint
    LENGTH = 24

    class << self
      # Works both with an Active Job instance, which is what the recorder sees
      # while a job runs, and with the Solid Queue row that stores its payload.
      # Both are fingerprinted from the serialized arguments, so the two sides
      # agree on what "the same job" means.
      def for(job)
        for_arguments(serialized_arguments(job))
      end

      def for_arguments(arguments)
        return if arguments.nil?

        Digest::SHA256.hexdigest(canonicalize(arguments).to_json)[0, LENGTH]
      end

      # Two payloads that differ only in the order of their keys describe the
      # same work, so keys are sorted before they are compared.
      def canonicalize(value)
        case value
        when Hash then value.sort_by { |key, _| key.to_s }.map { |key, nested| [ key.to_s, canonicalize(nested) ] }
        when Array then value.map { |item| canonicalize(item) }
        else value
        end
      end

      private
        def serialized_arguments(job)
          if job.respond_to?(:serialize) then job.serialize["arguments"]
          elsif job.respond_to?(:arguments) && job.arguments.is_a?(Hash) then job.arguments["arguments"]
          end
        rescue StandardError
          nil
        end
    end
  end
end
