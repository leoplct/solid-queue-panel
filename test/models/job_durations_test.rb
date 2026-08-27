# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class JobDurationsTest < TestCase
    test "uses the durations measured by the recorder when they exist" do
      JobUsage.create!(class_name: "ReportJob", bucket_at: JobUsage.bucket_for(Time.current),
                       executions: 4, wall_ms: 8_000, cpu_ms: 4_000)

      durations = JobDurations.new

      assert_equal :measured, durations.basis
      assert_in_delta 2.0, durations.average_seconds("ReportJob"), 0.01
      assert_equal :class, durations.for_class("ReportJob").scope
      assert_equal 4, durations.for_class("ReportJob").runs
    end

    test "the same job with the same arguments wins over the class as a whole" do
      job = create_job(class_name: "SyncJob", arguments: [ 10 ])
      JobUsage.create!(class_name: "SyncJob", bucket_at: JobUsage.bucket_for(Time.current), executions: 10, wall_ms: 20_000)
      JobUsage.create!(class_name: "SyncJob", arguments_fingerprint: ArgumentsFingerprint.for(job),
                       bucket_at: JobUsage.bucket_for(Time.current), executions: 3, wall_ms: 180_000)

      estimate = JobDurations.new.for_job(job)

      assert_equal :arguments, estimate.scope
      assert_in_delta 60.0, estimate.seconds, 0.01
      assert_equal 3, estimate.runs
    end

    test "arguments with no history fall back to the class" do
      JobUsage.create!(class_name: "SyncJob", bucket_at: JobUsage.bucket_for(Time.current), executions: 10, wall_ms: 20_000)
      job = create_job(class_name: "SyncJob", arguments: [ 999 ])

      estimate = JobDurations.new.for_job(job)

      assert_equal :class, estimate.scope
      assert_in_delta 2.0, estimate.seconds, 0.01
    end

    test "a job nothing is known about has no estimate" do
      assert_nil JobDurations.new.for_job(create_job(class_name: "SyncJob", arguments: [ 1 ]))
    end

    test "falls back to the time from enqueue to completion" do
      job = create_job(class_name: "ReportJob", status: :finished)
      job.update!(created_at: 6.seconds.ago, finished_at: Time.current)

      durations = JobDurations.new

      assert_equal :estimated, durations.basis
      assert_in_delta 6.0, durations.average_seconds("ReportJob"), 1
    end

    test "without the resource metrics tables it estimates from finished jobs" do
      job = create_job(class_name: "ReportJob", status: :finished)
      job.update!(created_at: 4.seconds.ago, finished_at: Time.current)

      without_resource_metrics do
        assert_equal :estimated, JobDurations.new.basis
      end
    end

    test "an unknown class has no estimate rather than a guess" do
      JobUsage.create!(class_name: "ReportJob", bucket_at: JobUsage.bucket_for(Time.current), executions: 1, wall_ms: 4_000)

      assert_nil JobDurations.new.average_seconds("NeverSeenJob")
    end

    test "with no history at all nothing is estimated" do
      durations = JobDurations.new

      assert_equal :unknown, durations.basis
      assert_not_predicate durations, :known?
      assert_nil durations.average_seconds("ReportJob")
    end
  end
end
