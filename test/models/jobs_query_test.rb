# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class JobsQueryTest < TestCase
    setup do
      @queued = create_job(status: :queued, queue_name: "default")
      @scheduled = create_job(status: :scheduled, queue_name: "reports")
      @failed = create_job(status: :failed, class_name: "BrokenJob")
      @finished = create_job(status: :finished)
      @blocked = create_job(status: :blocked)
      @in_progress = create_job(status: :in_progress)
    end

    test "defaults to every job, newest first" do
      query = JobsQuery.new

      assert_equal "all", query.status
      assert_equal 6, query.count
      assert_equal SolidQueue::Job.order(id: :desc).first, query.scope.first
    end

    test "filters by status" do
      assert_equal [ @queued.id ], JobsQuery.new(status: "queued").scope.ids
      assert_equal [ @scheduled.id ], JobsQuery.new(status: "scheduled").scope.ids
      assert_equal [ @failed.id ], JobsQuery.new(status: "failed").scope.ids
      assert_equal [ @finished.id ], JobsQuery.new(status: "finished").scope.ids
      assert_equal [ @blocked.id ], JobsQuery.new(status: "blocked").scope.ids
      assert_equal [ @in_progress.id ], JobsQuery.new(status: "in_progress").scope.ids
    end

    test "falls back to all jobs on an unknown status" do
      assert_equal "all", JobsQuery.new(status: "nonsense").status
    end

    test "filters by queue" do
      assert_equal [ @scheduled.id ], JobsQuery.new(queue_name: "reports").scope.ids
    end

    test "searches by class name, job id and Active Job id" do
      assert_equal [ @failed.id ], JobsQuery.new(search: "Broken").scope.ids
      assert_equal [ @queued.id ], JobsQuery.new(search: @queued.id.to_s).scope.ids
      assert_equal [ @queued.id ], JobsQuery.new(search: @queued.active_job_id).scope.ids
    end

    test "escapes wildcards in the search term" do
      assert_empty JobsQuery.new(search: "%Job").scope.ids
    end

    test "paginates" do
      pagination = Pagination.new(page: 2, per_page: 4, total_count: JobsQuery.new.count)

      assert_equal 2, JobsQuery.new.page(pagination).size
    end
  end
end
