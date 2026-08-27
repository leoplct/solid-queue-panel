# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class HealthTest < TestCase
    test "warns when no process is registered" do
      assert_match(/No Solid Queue process/, Health.new.alerts.first.message)
    end

    test "warns about processes without a heartbeat" do
      create_process(kind: "Supervisor", name: "supervisor-1").update!(last_heartbeat_at: 1.day.ago)

      messages = Health.new.alerts.map(&:message)

      assert(messages.any? { |message| message.include?("stopped sending heartbeats") })
    end

    test "warns about paused queues" do
      create_process(kind: "Supervisor", name: "supervisor-1")
      SolidQueue::Queue.find_by_name("reports").pause

      messages = Health.new.alerts.map(&:message)

      assert(messages.any? { |message| message.include?("paused") })
    end

    test "is quiet when everything is fine" do
      supervisor = create_process(kind: "Supervisor", name: "supervisor-1")
      create_process(kind: "Worker", name: "worker-1", supervisor: supervisor)

      assert_empty Health.new.alerts.select { |alert| alert.level != :info }
    end
  end
end
