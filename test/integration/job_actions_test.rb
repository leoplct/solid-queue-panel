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

  test "the duplicates page counts what would be discarded before anything is" do
    kept = create_job(class_name: "ReportJob", arguments: [ 7 ])
    2.times { create_job(class_name: "ReportJob", arguments: [ 7 ]) }

    get panel.duplicates_jobs_path

    assert_response :success
    assert_select "h2", text: /2 jobs would be discarded/
    assert_select "a[href=?]", panel.job_path(kept), text: "##{kept.id}"
    assert_select "form[action=?]", panel.remove_duplicates_jobs_path(status: "queued")
    assert_equal 3, SolidQueue::Job.count, "counting changes nothing"
  end

  test "the duplicates page can be scoped to one queue" do
    2.times { create_job(queue_name: "reports", arguments: [ 7 ]) }
    2.times { create_job(queue_name: "mailers", arguments: [ 7 ]) }

    get panel.duplicates_jobs_path(queue_name: "reports")

    assert_response :success
    assert_select "h2", text: /1 job would be discarded/
    assert_select "form[action=?]", panel.remove_duplicates_jobs_path(queue_name: "reports", status: "queued")
  end

  test "the duplicates page says when there is nothing to do" do
    create_job(arguments: [ 1 ])

    get panel.duplicates_jobs_path

    assert_response :success
    assert_select "h2", text: /Nothing to discard/
  end

  test "removing duplicates keeps the first copy of each queued job" do
    kept = create_job(class_name: "ReportJob", arguments: [ 7 ])
    duplicate = create_job(class_name: "ReportJob", arguments: [ 7 ])
    other = create_job(class_name: "ReportJob", arguments: [ 8 ])

    post panel.remove_duplicates_jobs_path(status: "queued")

    assert_redirected_to panel.jobs_path(status: "queued")
    assert_equal "Discarded 1 duplicate job: 3 queued jobs scanned.", flash[:notice]
    assert_equal [ kept.id, other.id ].sort, SolidQueue::Job.pluck(:id).sort
    assert_not SolidQueue::Job.exists?(duplicate.id)
  end

  test "removing duplicates can be limited to one queue" do
    2.times { create_job(queue_name: "reports", arguments: [ 7 ]) }
    2.times { create_job(queue_name: "mailers", arguments: [ 7 ]) }

    post panel.remove_duplicates_jobs_path(status: "queued", queue_name: "reports")

    assert_equal 1, SolidQueue::Job.where(queue_name: "reports").count
    assert_equal 2, SolidQueue::Job.where(queue_name: "mailers").count
  end

  test "removing duplicates says so when there is nothing to remove" do
    create_job(arguments: [ 1 ])

    post panel.remove_duplicates_jobs_path(status: "queued")

    assert_equal "No exact duplicate found: 1 queued job scanned.", flash[:notice]
  end

  test "an unknown bulk action changes nothing" do
    job = create_job(status: :queued)

    post panel.bulk_jobs_path, params: { job_ids: [ job.id ], bulk_action: "explode" }

    assert SolidQueue::Job.exists?(job.id)
  end
end
