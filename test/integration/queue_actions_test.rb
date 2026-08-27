# frozen_string_literal: true

require "test_helper"

class QueueActionsTest < SolidQueuePanel::IntegrationTestCase
  test "pausing and resuming a queue" do
    create_job(queue_name: "reports")

    post panel.pause_queue_path("reports")
    assert SolidQueue::Queue.find_by_name("reports").paused?

    post panel.resume_queue_path("reports")
    assert_not SolidQueue::Queue.find_by_name("reports").paused?
  end

  test "clearing a queue discards its queued jobs" do
    create_job(queue_name: "reports")
    kept = create_job(queue_name: "default")

    delete panel.clear_queue_path("reports")

    assert_redirected_to panel.queues_path
    assert_equal [ kept.id ], SolidQueue::Job.pluck(:id)
  end

  test "pruning removes processes without a heartbeat" do
    alive = create_process(name: "alive")
    create_process(name: "dead").update!(last_heartbeat_at: 1.day.ago)

    post panel.prune_processes_path

    assert_equal [ alive.id ], SolidQueue::Process.pluck(:id)
  end
end
