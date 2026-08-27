# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class RunAllJobsTest < TestCase
    test "enqueues every failed job again" do
      jobs = Array.new(3) { create_job(status: :failed) }
      create_job(status: :queued)

      result = RunAllJobs.new(JobsQuery.new(status: "failed")).run

      assert_equal 3, result.count
      assert_equal 0, SolidQueue::FailedExecution.count
      assert_equal 4, SolidQueue::ReadyExecution.count
      assert(jobs.all? { |job| job.reload.ready_execution.present? })
      assert_not result.capped?
    end

    test "resets the attempts of the failed jobs it enqueues" do
      job = create_job(status: :failed)
      job.update!(arguments: job.arguments.merge("executions" => 3))

      RunAllJobs.new(JobsQuery.new(status: "failed")).run

      assert_equal 0, job.reload.arguments["executions"]
    end

    test "makes every scheduled job due now" do
      jobs = Array.new(2) { create_job(status: :scheduled) }

      result = RunAllJobs.new(JobsQuery.new(status: "scheduled")).run

      assert_equal 2, result.count
      assert(jobs.all? { |job| job.reload.scheduled_execution.scheduled_at <= Time.current })
      assert(jobs.all? { |job| job.reload.scheduled_at <= Time.current })
    end

    test "releases the blocked jobs whose concurrency limit has room" do
      4.times { create_job(class_name: "ConcurrentJob", arguments: [ 1 ], concurrency_key: "imports") }

      assert_equal 2, SolidQueue::BlockedExecution.count, "two jobs took the two slots, two are blocked"

      SolidQueue::ReadyExecution.delete_all
      SolidQueue::Semaphore.update_all(value: 1)

      result = RunAllJobs.new(JobsQuery.new(status: "blocked")).run

      assert_equal 1, result.count, "only one slot was free"
      assert_equal 1, result.attempted - result.count, "the other stays blocked"
      assert_equal 1, SolidQueue::ReadyExecution.count
    end

    test "a blocked job with no room stays blocked" do
      2.times { create_job(class_name: "ConcurrentJob", arguments: [ 1 ], concurrency_key: "imports") }
      SolidQueue::ReadyExecution.delete_all

      result = RunAllJobs.new(JobsQuery.new(status: "blocked")).run

      assert_not result.any?
      assert_equal 0, SolidQueue::ReadyExecution.count
    end

    test "only the jobs of the filtered list are touched" do
      create_job(status: :failed, queue_name: "reports")
      untouched = create_job(status: :failed, queue_name: "mailers")

      result = RunAllJobs.new(JobsQuery.new(status: "failed", queue_name: "reports")).run

      assert_equal 1, result.count
      assert untouched.reload.failed_execution.present?
    end

    test "there is nothing to run on the other lists" do
      create_job(status: :queued)

      %w[all queued in_progress finished].each do |status|
        query = JobsQuery.new(status: status)

        assert_not RunAllJobs.new(query).available?, "#{status} should have nothing to run"
        assert_equal 0, RunAllJobs.new(query).run.count
      end
    end
  end
end
