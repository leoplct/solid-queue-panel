# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class ResourceReportTest < TestCase
    setup do
      create_process(name: "worker-1", metadata: { "queues" => "*", "thread_pool_size" => 5 })
    end

    test "groups the latest sample of every process by machine" do
      sample("worker-1", rss_kb: 100_000, at: 3.minutes.ago)
      sample("worker-1", rss_kb: 260_000)
      sample("worker-2", rss_kb: 240_000)
      sample("worker-3", rss_kb: 200_000, hostname: "jobs-02")

      report = ResourceReport.new
      hosts = report.hosts.index_by(&:hostname)

      assert_equal %w[jobs-01 jobs-02], report.hosts.map(&:hostname)
      assert_equal 2, hosts["jobs-01"].samples.size
      assert_equal 500_000, hosts["jobs-01"].solid_queue_memory_kb
      assert_equal 250_000, hosts["jobs-01"].worker_memory_kb
      assert_equal 5, hosts["jobs-01"].threads_per_worker
      assert_equal 10, hosts["jobs-01"].total_worker_threads
    end

    test "reports nothing until the tables are installed" do
      sample("worker-1")

      without_resource_metrics do
        report = ResourceReport.new

        assert_not_predicate report, :installed?
        assert_not_predicate report, :any?
        assert_empty report.hosts
      end
    end

    test "readings older than a few minutes are not the current state" do
      sample("worker-1", at: 30.minutes.ago)

      assert_not_predicate ResourceReport.new, :any?
    end

    test "series are bucketed over the period" do
      sample("worker-1", rss_kb: 204_800, at: 3.hours.ago)
      sample("worker-1", rss_kb: 307_200)

      report = ResourceReport.new(period: TimePeriod.new(24))
      series = report.worker_memory_series(report.hosts.sole)
      values = series.filter_map(&:last)

      assert_equal 25, series.size, "one bucket an hour, plus the one in progress"
      assert_includes values, 200.0
      assert_equal 300.0, values.last
    end

    test "the heaviest job classes come first" do
      usage("ReportJob", cpu_ms: 9_000, executions: 3)
      usage("MailerJob", cpu_ms: 1_000, executions: 10)
      sample("worker-1")

      report = ResourceReport.new
      heaviest = report.heaviest_jobs

      assert_equal %w[ReportJob MailerJob], heaviest.map(&:class_name)
      assert_equal 3_000, heaviest.first.average_cpu_ms
      assert_equal 10_000, report.total_cpu_ms
      assert_in_delta 90.0, heaviest.first.cpu_share_of(report.total_cpu_ms), 0.1
    end

    private
      def sample(name, rss_kb: 250_000, hostname: "jobs-01", at: Time.current)
        ProcessSample.create!(
          name: name, kind: "Worker", hostname: hostname, pid: 1, rss_kb: rss_kb, cpu_percent: 30.0,
          threads: 9, cpu_count: 4, load_average: 2.0, memory_kb: 8_000_000, available_memory_kb: 4_000_000,
          created_at: at
        )
      end

      def usage(class_name, cpu_ms:, executions:)
        JobUsage.create!(class_name: class_name, bucket_at: JobUsage.bucket_for(Time.current),
                         executions: executions, cpu_ms: cpu_ms, wall_ms: cpu_ms * 2, max_rss_kb: 300_000)
      end
  end
end
