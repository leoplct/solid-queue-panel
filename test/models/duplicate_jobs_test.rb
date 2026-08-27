# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class DuplicateJobsTest < TestCase
    test "discards the later copies of identical queued jobs" do
      first = create_job(class_name: "ReportJob", arguments: [ 42 ])
      second = create_job(class_name: "ReportJob", arguments: [ 42 ])
      third = create_job(class_name: "ReportJob", arguments: [ 42 ])

      result = DuplicateJobs.new.discard_all

      assert_equal 2, result.discarded
      assert_equal 3, result.scanned
      assert_equal [ first.id ], SolidQueue::Job.pluck(:id)
      assert_not SolidQueue::Job.exists?(second.id)
      assert_not SolidQueue::Job.exists?(third.id)
    end

    test "different arguments are not duplicates" do
      create_job(class_name: "ReportJob", arguments: [ 1 ])
      create_job(class_name: "ReportJob", arguments: [ 2 ])
      create_job(class_name: "ReportJob", arguments: [ "1" ])

      assert_equal 0, DuplicateJobs.new.discard_all.discarded
      assert_equal 3, SolidQueue::Job.count
    end

    test "the same arguments in a different class or queue are not duplicates" do
      create_job(class_name: "ReportJob", queue_name: "default", arguments: [ 1 ])
      create_job(class_name: "MailerJob", queue_name: "default", arguments: [ 1 ])
      create_job(class_name: "ReportJob", queue_name: "reports", arguments: [ 1 ])

      assert_equal 0, DuplicateJobs.new.discard_all.discarded
    end

    test "a different priority is not a duplicate" do
      create_job(class_name: "ReportJob", arguments: [ 1 ])
      create_job(class_name: "ReportJob", arguments: [ 1 ]).update!(priority: 5)

      assert_equal 0, DuplicateJobs.new.discard_all.discarded
    end

    test "a different number of attempts is not a duplicate" do
      create_job(class_name: "ReportJob", arguments: [ 1 ])
      retried = create_job(class_name: "ReportJob", arguments: [ 1 ])
      retried.update!(arguments: retried.arguments.merge("executions" => 1))

      assert_equal 0, DuplicateJobs.new.discard_all.discarded
    end

    test "the identifiers Active Job generates per job are ignored" do
      first = create_job(class_name: "ReportJob", arguments: [ 1 ])
      second = create_job(class_name: "ReportJob", arguments: [ 1 ])

      assert_not_equal first.arguments["job_id"], second.arguments["job_id"]
      assert_equal 1, DuplicateJobs.new.discard_all.discarded
    end

    test "the order of the payload keys does not matter" do
      first = create_job(class_name: "ReportJob", arguments: [ 1 ])
      second = create_job(class_name: "ReportJob", arguments: [ 1 ])
      second.update!(arguments: second.arguments.to_a.reverse.to_h)

      assert_equal 1, DuplicateJobs.new.discard_all.discarded
    end

    test "only one queue is scanned when a queue is given" do
      create_job(queue_name: "reports", arguments: [ 1 ])
      create_job(queue_name: "reports", arguments: [ 1 ])
      create_job(queue_name: "mailers", arguments: [ 1 ])
      create_job(queue_name: "mailers", arguments: [ 1 ])

      result = DuplicateJobs.new(queue_name: "reports").discard_all

      assert_equal 1, result.discarded
      assert_equal 2, result.scanned
      assert_equal 2, SolidQueue::Job.where(queue_name: "mailers").count
    end

    test "jobs that are not waiting in a queue are left alone" do
      create_job(status: :in_progress, arguments: [ 1 ])
      create_job(status: :scheduled, arguments: [ 1 ])
      create_job(status: :failed, arguments: [ 1 ])
      create_job(status: :finished, arguments: [ 1 ])
      create_job(status: :queued, arguments: [ 1 ])

      result = DuplicateJobs.new.discard_all

      assert_equal 0, result.discarded
      assert_equal 1, result.scanned
      assert_equal 5, SolidQueue::Job.count
    end

    test "the concurrency lock of a discarded job is released" do
      2.times { create_job(class_name: "ConcurrentJob", arguments: [ 1 ], concurrency_key: "imports") }

      assert_equal 0, SolidQueue::Semaphore.find_by(key: "imports").value, "both slots should be taken"
      assert_equal 1, DuplicateJobs.new.discard_all.discarded
      assert_equal 1, SolidQueue::Semaphore.find_by(key: "imports").value, "the slot should be given back"
    end

    test "the preview counts the copies without discarding anything" do
      3.times { create_job(class_name: "ReportJob", queue_name: "reports", arguments: [ 42 ]) }
      2.times { create_job(class_name: "MailerJob", queue_name: "reports", arguments: [ 7 ]) }
      create_job(class_name: "ReportJob", queue_name: "reports", arguments: [ 99 ])

      preview = DuplicateJobs.new.preview

      assert_predicate preview, :any?
      assert_equal 3, preview.count, "two copies of the first job and one of the second"
      assert_equal 6, preview.scanned
      assert_equal 6, SolidQueue::Job.count, "nothing is discarded by a preview"
      assert_not preview.capped?
      assert_not preview.partial_list?
    end

    test "the preview says what each group is and which job stays" do
      kept = create_job(class_name: "ReportJob", queue_name: "reports", arguments: [ 42 ])
      2.times { create_job(class_name: "ReportJob", queue_name: "reports", arguments: [ 42 ]) }

      group = DuplicateJobs.new.preview.groups.sole

      assert_equal "ReportJob", group.class_name
      assert_equal "reports", group.queue_name
      assert_equal [ 42 ], group.arguments
      assert_equal kept.id, group.kept_job_id
      assert_equal 2, group.discarded
      assert_equal 3, group.total
    end

    test "the preview of a queue only looks at that queue" do
      2.times { create_job(queue_name: "reports", arguments: [ 1 ]) }
      2.times { create_job(queue_name: "mailers", arguments: [ 1 ]) }

      preview = DuplicateJobs.new(queue_name: "reports").preview

      assert_equal 1, preview.count
      assert_equal 2, preview.scanned
    end

    test "a preview with nothing to discard says so" do
      2.times { |index| create_job(arguments: [ index ]) }

      preview = DuplicateJobs.new.preview

      assert_not preview.any?
      assert_equal 0, preview.count
      assert_empty preview.groups
    end

    test "reports how many jobs were scanned when nothing is duplicated" do
      2.times { |index| create_job(arguments: [ index ]) }

      result = DuplicateJobs.new.discard_all

      assert_not result.any?
      assert_equal 2, result.scanned
      assert_not result.capped?
    end
  end
end
