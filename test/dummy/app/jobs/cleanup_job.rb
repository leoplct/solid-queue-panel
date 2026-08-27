# frozen_string_literal: true

class CleanupJob < ActiveJob::Base
  queue_as :default

  def perform(*)
    # The dummy application never actually runs jobs.
  end
end
