# frozen_string_literal: true

# Used by the tests to check that discarding a job releases the concurrency
# lock it was holding.
class ConcurrentJob < ActiveJob::Base
  limits_concurrency to: 2, key: ->(*) { "imports" }

  def perform(*)
    # The dummy application never actually runs jobs.
  end
end
