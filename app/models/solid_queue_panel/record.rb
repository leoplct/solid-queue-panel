# frozen_string_literal: true

module SolidQueuePanel
  # Base class of the tables the panel adds. It inherits from SolidQueue::Record
  # so that the resource metrics land in the same database as the queue itself,
  # whatever the application configured.
  class Record < SolidQueue::Record
    self.abstract_class = true
  end
end
