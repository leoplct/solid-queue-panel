# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class ThroughputTest < TestCase
    test "buckets enqueued, finished and failed jobs over the period" do
      2.times { create_job(status: :finished) }
      create_job(status: :failed)

      throughput = Throughput.new(period: TimePeriod.new(24))

      assert_equal 3, throughput.enqueued
      assert_equal 2, throughput.finished
      assert_equal 1, throughput.failed
      assert_equal 25, throughput.points.size
      assert_predicate throughput, :any?
      assert_in_delta 33.3, throughput.failure_rate, 0.1
    end

    test "is empty when nothing ran" do
      throughput = Throughput.new(period: TimePeriod.new(1))

      assert_equal 0, throughput.finished
      assert_not throughput.any?
      assert_equal 0.0, throughput.failure_rate
    end

    test "reports arrival and completion rates" do
      2.times { create_job(status: :finished) }

      throughput = Throughput.new(period: TimePeriod.new(1))

      assert_in_delta 2 / 3600.0, throughput.enqueued_rate, 0.0001
      assert_in_delta 2 / 3600.0, throughput.completion_rate, 0.0001
      assert_not throughput.falling_behind?
    end

    test "knows when jobs arrive faster than they are processed" do
      5.times { create_job(status: :queued) }
      create_job(status: :finished)

      assert_predicate Throughput.new(period: TimePeriod.new(1)), :falling_behind?
    end

    test "buckets get smaller as the period gets shorter" do
      assert_equal 3600, Throughput.new(period: TimePeriod.new(24)).bucket_size
      assert_equal 150, Throughput.new(period: TimePeriod.new(1)).bucket_size
    end
  end
end
