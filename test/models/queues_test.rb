# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class QueuesTest < TestCase
    test "counts every execution state per queue" do
      create_job(queue_name: "reports", status: :queued)
      create_job(queue_name: "reports", status: :queued)
      create_job(queue_name: "reports", status: :scheduled)
      create_job(queue_name: "reports", status: :failed)
      create_job(queue_name: "reports", status: :in_progress)
      create_job(queue_name: "mailers", status: :queued)

      reports = Queues.new.find { |queue| queue.name == "reports" }

      assert_equal 2, reports.ready
      assert_equal 1, reports.scheduled
      assert_equal 1, reports.failed
      assert_equal 1, reports.in_progress
      assert_equal 3, reports.pending
      assert_not reports.empty?
    end

    test "lists queues that only exist because a worker polls them" do
      create_process(metadata: { "queues" => "critical,background", "thread_pool_size" => 3 })

      names = Queues.new.map(&:name)

      assert_includes names, "critical"
      assert_includes names, "background"
    end

    test "ignores wildcard queue patterns" do
      create_process(metadata: { "queues" => "*" })

      assert_empty Queues.new.map(&:name)
    end

    test "knows when a queue is paused" do
      create_job(queue_name: "reports")
      SolidQueue::Queue.find_by_name("reports").pause

      assert_predicate Queues.new.find_by_name("reports"), :paused?
    end

    test "latency is the age of the oldest queued job" do
      create_job(queue_name: "reports")
      SolidQueue::ReadyExecution.update_all(created_at: 5.minutes.ago)

      assert_in_delta 300, Queues.new.find_by_name("reports").latency, 5
    end
  end
end
