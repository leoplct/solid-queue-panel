# frozen_string_literal: true

require "test_helper"

class JobActionsTest < SolidQueuePanel::IntegrationTestCase
  test "retrying a failed job puts it back in its queue" do
    job = create_job(status: :failed)

    post panel.retry_job_path(job)

    assert_redirected_to panel.root_path
    assert_nil job.reload.failed_execution
    assert job.reload.ready_execution.present?
  end

  test "running a scheduled job now moves its due date" do
    job = create_job(status: :scheduled)

    post panel.dispatch_now_job_path(job)

    assert_operator job.reload.scheduled_execution.scheduled_at, :<=, Time.current
  end

  test "discarding a job deletes it" do
    job = create_job(status: :queued)

    delete panel.job_path(job)

    assert_redirected_to panel.jobs_path
    assert_not SolidQueue::Job.exists?(job.id)
  end

  test "discarding a finished job deletes it" do
    job = create_job(status: :finished)

    delete panel.job_path(job)

    assert_not SolidQueue::Job.exists?(job.id)
  end

  test "a job in progress cannot be discarded" do
    job = create_job(status: :in_progress)

    delete panel.job_path(job)

    assert SolidQueue::Job.exists?(job.id)
    assert_equal "Can't discard a job in progress", flash[:alert]
  end

  test "bulk retry enqueues every selected job" do
    jobs = Array.new(3) { create_job(status: :failed) }

    post panel.bulk_jobs_path, params: { job_ids: jobs.map(&:id), bulk_action: "retry" }

    assert_equal 0, SolidQueue::FailedExecution.count
    assert_equal 3, SolidQueue::ReadyExecution.count
  end

  test "bulk discard removes every selected job" do
    jobs = Array.new(2) { create_job(status: :queued) }

    post panel.bulk_jobs_path, params: { job_ids: jobs.map(&:id), bulk_action: "discard" }

    assert_equal 0, SolidQueue::Job.count
  end

  test "an unknown bulk action changes nothing" do
    job = create_job(status: :queued)

    post panel.bulk_jobs_path, params: { job_ids: [ job.id ], bulk_action: "explode" }

    assert SolidQueue::Job.exists?(job.id)
  end
end
