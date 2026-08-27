# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class QueueTrendsTest < TestCase
    test "counts what arrived and what was finished, per queue and per bucket" do
      2.times { create_job(queue_name: "reports") }
      finished = create_job(queue_name: "reports", status: :finished)
      create_job(queue_name: "mailers")

      trends = QueueTrends.new(period: TimePeriod.new(24))

      assert_equal 3, trends.enqueued("reports")
      assert_equal 1, trends.finished("reports")
      assert_equal 1, trends.enqueued("mailers")
      assert_equal 0, trends.finished("mailers")
      assert_not_nil finished.finished_at
    end

    test "every queue gets one point per bucket, plus the one in progress" do
      create_job(queue_name: "reports")

      assert_equal 25, QueueTrends.new(period: TimePeriod.new(24)).for("reports").size
    end

    test "a queue with no history is a flat line rather than nothing" do
      trend = QueueTrends.new.for("never-used")

      assert_equal 25, trend.size
      assert(trend.all? { |point| point.peak.zero? })
      assert_not QueueTrends.new.any?("never-used")
    end

    test "work is counted in the bucket it became due in" do
      create_job(queue_name: "reports", status: :scheduled, scheduled_at: 3.hours.ago)
      create_job(queue_name: "reports", status: :scheduled, scheduled_at: 2.days.ago)

      trends = QueueTrends.new(period: TimePeriod.new(24))

      assert_equal 1, trends.enqueued("reports"), "the job due two days ago is outside the period"
      assert trends.any?("reports")
    end
  end
end
