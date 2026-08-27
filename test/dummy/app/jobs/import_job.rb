# frozen_string_literal: true

class ImportJob < ActiveJob::Base
  def perform(*)
    # The dummy application never actually runs jobs.
  end
end
