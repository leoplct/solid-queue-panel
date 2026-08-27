# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class RecorderTest < TestCase
    setup do
      @machine = FakeMachine.new
      @recorder = Recorder.new(kind: "Worker", machine: @machine)
    end

    test "a tick writes down what the process and the machine are using" do
      create_process(name: "worker-1")
      SolidQueue::Process.update_all(hostname: @machine.hostname, pid: Process.pid)

      @recorder.tick

      sample = ProcessSample.sole

      assert_equal "worker-1", sample.name
      assert_equal "Worker", sample.kind
      assert_equal @machine.hostname, sample.hostname
      assert_equal 250_000, sample.rss_kb
      assert_equal 4, sample.cpu_count
      assert_equal 8_000_000, sample.memory_kb
      assert_equal SolidQueue::Process.first.id, sample.process_id
    end

    test "a process Solid Queue has not registered is still recorded" do
      @recorder.tick

      assert_nil ProcessSample.sole.process_id
      assert_match(/worker-/, ProcessSample.sole.name)
    end

    test "job usage is accumulated in memory and written on the tick" do
      @recorder.track(class_name: "ReportJob", arguments_fingerprint: "abc", cpu_ms: 100, wall_ms: 250, memory_growth_kb: 40, rss_kb: 300_000, failed: false)
      @recorder.track(class_name: "ReportJob", arguments_fingerprint: "abc", cpu_ms: 300, wall_ms: 450, memory_growth_kb: 10, rss_kb: 280_000, failed: true)

      assert_equal 0, JobUsage.count

      @recorder.tick
      usage = JobUsage.totals.sole

      assert_equal "ReportJob", usage.class_name
      assert_equal 2, usage.executions
      assert_equal 1, usage.failures
      assert_equal 400, usage.cpu_ms
      assert_equal 700, usage.wall_ms
      assert_equal 50, usage.memory_growth_kb
      assert_equal 300_000, usage.max_rss_kb
      assert_equal 200, usage.average_cpu_ms
    end

    test "the same hour keeps adding to the same bucket" do
      @recorder.track(class_name: "ReportJob", arguments_fingerprint: "abc", cpu_ms: 100, wall_ms: 100, memory_growth_kb: 0, rss_kb: 1, failed: false)
      @recorder.tick
      @recorder.track(class_name: "ReportJob", arguments_fingerprint: "abc", cpu_ms: 100, wall_ms: 100, memory_growth_kb: 0, rss_kb: 1, failed: false)
      @recorder.tick

      assert_equal 2, JobUsage.totals.sole.executions
    end

    test "the subscriber measures one job execution" do
      subscriber = Recorder::JobSubscriber.new(@recorder, @machine)
      job = ReportJob.new

      subscriber.start("perform.active_job", "1", job: job)
      subscriber.finish("perform.active_job", "1", job: job)
      @recorder.tick

      usage = JobUsage.totals.sole

      assert_equal "ReportJob", usage.class_name
      assert_equal 1, usage.executions
      assert_equal 0, usage.failures
    end

    test "the subscriber counts a raised job as a failure" do
      subscriber = Recorder::JobSubscriber.new(@recorder, @machine)
      job = ReportJob.new

      subscriber.start("perform.active_job", "1", job: job)
      subscriber.finish("perform.active_job", "1", job: job, exception: [ "RuntimeError", "boom" ])
      @recorder.tick

      assert_equal 1, JobUsage.totals.sole.failures
    end

    test "each set of arguments gets its own row, on top of the total of the class" do
      @recorder.track(class_name: "SyncJob", arguments_fingerprint: "small", cpu_ms: 100, wall_ms: 1_000, memory_growth_kb: 0, rss_kb: 1, failed: false)
      @recorder.track(class_name: "SyncJob", arguments_fingerprint: "big", cpu_ms: 900, wall_ms: 60_000, memory_growth_kb: 0, rss_kb: 1, failed: false)
      @recorder.tick

      assert_equal 2, JobUsage.totals.sole.executions
      assert_equal 61_000, JobUsage.totals.sole.wall_ms
      assert_equal %w[big small], JobUsage.by_arguments.order(:arguments_fingerprint).pluck(:arguments_fingerprint)
      assert_equal 60_000, JobUsage.find_by(arguments_fingerprint: "big").wall_ms
    end

    test "only the most frequent sets of arguments are remembered" do
      (Recorder::MAX_ARGUMENT_SETS + 5).times do |index|
        (index + 1).times do
          @recorder.track(class_name: "SyncJob", arguments_fingerprint: "args-#{index}", cpu_ms: 1, wall_ms: 1, memory_growth_kb: 0, rss_kb: 1, failed: false)
        end
      end
      @recorder.tick

      assert_equal Recorder::MAX_ARGUMENT_SETS, JobUsage.by_arguments.count
      assert_includes JobUsage.by_arguments.pluck(:arguments_fingerprint), "args-#{Recorder::MAX_ARGUMENT_SETS + 4}"
      assert_not_includes JobUsage.by_arguments.pluck(:arguments_fingerprint), "args-0"
    end

    test "old readings are pruned" do
      ProcessSample.create!(name: "old", kind: "Worker", hostname: "host", pid: 1, rss_kb: 1, created_at: 4.days.ago)
      ProcessSample.create!(name: "new", kind: "Worker", hostname: "host", pid: 1, rss_kb: 1, created_at: Time.current)
      JobUsage.create!(class_name: "OldJob", bucket_at: 4.days.ago, executions: 1)

      ProcessSample.prune(3.days)
      JobUsage.prune(3.days)

      assert_equal [ "new" ], ProcessSample.pluck(:name)
      assert_equal 0, JobUsage.count
    end

    class FakeMachine
      def hostname = "jobs-01"
      def rss_kb = 250_000
      def cpu_count = 4
      def load_average = 2.0
      def memory_kb = 8_000_000
      def available_memory_kb = 4_000_000
      def process_cpu_time = 1.5
    end
  end
end
