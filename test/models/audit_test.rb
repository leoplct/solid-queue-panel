# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class AuditTest < TestCase
    setup do
      @logger = Class.new do
        attr_reader :lines

        def initialize = @lines = []
        def info(message = nil) = @lines << (message || yield)
      end.new

      SolidQueuePanel.configuration.audit_logger = @logger
    end

    teardown { SolidQueuePanel.configuration.audit_logger = nil }

    test "writes a line naming the action, the actor and what it touched" do
      Audit.record(:discard_job, actor: "alice@example.com", ip: "10.0.0.4", job_id: 7)

      assert_equal 1, @logger.lines.size
      assert_match "action=discard_job", @logger.lines.first
      assert_match "actor=alice@example.com", @logger.lines.first
      assert_match "ip=10.0.0.4", @logger.lines.first
      assert_match "job_id=7", @logger.lines.first
    end

    test "publishes an event applications can keep their own trail from" do
      entries = []
      subscription = ActiveSupport::Notifications.subscribe(Audit::EVENT) { |*, payload| entries << payload }

      Audit.record(:clear_queue, actor: "shared credentials", ip: "10.0.0.4", queue_name: "default")

      assert_equal 1, entries.size
      assert_equal "clear_queue", entries.first[:action]
      assert_equal "default", entries.first[:queue_name]
      assert_kind_of Time, entries.first[:at]
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    test "writes to the application logger until it is told otherwise" do
      SolidQueuePanel.configuration.audit_logger = nil

      assert_equal Rails.logger, SolidQueuePanel.configuration.audit_logger
    end
  end
end
