# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class MetricsTest < TestCase
    test "groups counters by job class" do
      create_job(class_name: "ReportJob", status: :finished)
      create_job(class_name: "ReportJob", status: :finished)
      create_job(class_name: "ReportJob", status: :failed)
      create_job(class_name: "MailerJob", status: :in_progress)

      rows = Metrics.new.rows.index_by(&:class_name)

      assert_equal 2, rows["ReportJob"].finished
      assert_equal 1, rows["ReportJob"].failed
      assert_equal 3, rows["ReportJob"].enqueued
      assert_in_delta 33.3, rows["ReportJob"].failure_rate, 0.1
      assert_equal 1, rows["MailerJob"].in_progress
    end

    test "measures the time between enqueue and completion" do
      job = create_job(status: :finished)
      job.update!(created_at: 10.seconds.ago, finished_at: Time.current)

      row = Metrics.new.rows.first

      assert_in_delta 10, row.average_duration, 1
      assert_in_delta 10, row.total_duration, 1
    end

    test "ignores jobs outside the period" do
      job = create_job(status: :finished)
      job.update!(created_at: 3.days.ago, finished_at: 3.days.ago)

      assert_empty Metrics.new(period: TimePeriod.new(1)).rows
    end
  end
end
