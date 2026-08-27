# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class JobDurationsTest < TestCase
    test "uses the durations measured by the recorder when they exist" do
      JobUsage.create!(class_name: "ReportJob", bucket_at: JobUsage.bucket_for(Time.current),
                       executions: 4, wall_ms: 8_000, cpu_ms: 4_000)

      durations = JobDurations.new

      assert_equal :measured, durations.source
      assert_in_delta 2.0, durations.average_seconds("ReportJob"), 0.01
    end

    test "falls back to the time from enqueue to completion" do
      job = create_job(class_name: "ReportJob", status: :finished)
      job.update!(created_at: 6.seconds.ago, finished_at: Time.current)

      durations = JobDurations.new

      assert_equal :estimated, durations.source
      assert_in_delta 6.0, durations.average_seconds("ReportJob"), 1
    end

    test "without the resource metrics tables it estimates from finished jobs" do
      job = create_job(class_name: "ReportJob", status: :finished)
      job.update!(created_at: 4.seconds.ago, finished_at: Time.current)

      without_resource_metrics do
        assert_equal :estimated, JobDurations.new.source
      end
    end

    test "an unknown class falls back to the average of the others" do
      JobUsage.create!(class_name: "ReportJob", bucket_at: JobUsage.bucket_for(Time.current), executions: 1, wall_ms: 4_000)

      assert_in_delta 4.0, JobDurations.new.average_seconds("NeverSeenJob"), 0.01
    end

    test "with no history at all every job counts as one second" do
      durations = JobDurations.new

      assert_equal :unknown, durations.source
      assert_in_delta 1.0, durations.average_seconds("ReportJob"), 0.01
    end
  end
end
