# frozen_string_literal: true

require "test_helper"

class AuditTrailTest < SolidQueuePanel::IntegrationTestCase
  setup do
    @entries = []
    @subscription = ActiveSupport::Notifications.subscribe(SolidQueuePanel::Audit::EVENT) { |*, payload| @entries << payload }
  end

  teardown do
    ActiveSupport::Notifications.unsubscribe(@subscription)
    SolidQueuePanel.configuration.instance_variable_set(:@audit_actor_block, nil)
  end

  test "discarding a job is written down with the job it discarded" do
    job = create_job(status: :queued)

    delete panel.job_path(job)

    assert_equal "discard_job", @entries.sole[:action]
    assert_equal job.id, @entries.sole[:job_id]
  end

  test "retrying a failed job is written down" do
    job = create_job(status: :failed)

    post panel.retry_job_path(job)

    assert_equal "retry_job", @entries.sole[:action]
  end

  test "pausing and resuming a queue are written down" do
    create_job(status: :queued, queue_name: "reports")

    post panel.pause_queue_path(name: "reports")
    post panel.resume_queue_path(name: "reports")

    assert_equal %w[pause_queue resume_queue], @entries.map { |entry| entry[:action] }
    assert_equal [ "reports", "reports" ], @entries.map { |entry| entry[:queue_name] }
  end

  test "clearing a queue is written down" do
    create_job(status: :queued, queue_name: "reports")

    delete panel.clear_queue_path(name: "reports")

    assert_equal "clear_queue", @entries.sole[:action]
  end

  test "a bulk discard records how many went and which" do
    jobs = 2.times.map { create_job(status: :queued) }

    post panel.bulk_jobs_path, params: { bulk_action: "discard", job_ids: jobs.map(&:id) }

    assert_equal "bulk_discard_jobs", @entries.sole[:action]
    assert_equal 2, @entries.sole[:count]
    assert_equal jobs.map(&:id).join(","), @entries.sole[:job_ids]
  end

  test "the actor is named by the application when it knows who is asking" do
    SolidQueuePanel.configuration.audit_actor { "alice@example.com" }
    job = create_job(status: :queued)

    delete panel.job_path(job)

    assert_equal "alice@example.com", @entries.sole[:actor]
  end

  # A shared password identifies nobody, and the trail says so rather than
  # implying an identity the panel does not have.
  test "the actor says how the request was authenticated when nobody is named" do
    SolidQueuePanel.configuration.username = "admin"
    SolidQueuePanel.configuration.password = "secret"
    sign_in

    delete panel.job_path(create_job(status: :queued))

    assert_equal "shared credentials", @entries.sole[:actor]
  end

  test "nothing is written down when the panel is read only" do
    SolidQueuePanel.configuration.read_only = true

    delete panel.job_path(create_job(status: :queued))

    assert_empty @entries
  end

  private
    def sign_in
      post panel.login_path, params: { username: "admin", password: "secret" }
    end
end
