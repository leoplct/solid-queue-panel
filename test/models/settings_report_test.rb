# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class SettingsReportTest < TestCase
    setup do
      create_process(name: "worker-1", metadata: { "queues" => "reports,mailers", "thread_pool_size" => 5, "polling_interval" => 0.1 })
      create_job(queue_name: "reports")
      create_job(queue_name: "reports", status: :failed)
    end

    test "describes the installation from top to bottom" do
      report = SettingsReport.new.to_s

      assert_match "# Solid Queue report", report
      assert_match "## Versions", report
      assert_match "solid_queue: #{SolidQueue::VERSION}", report
      assert_match "## Solid Queue configuration", report
      assert_match "preserve_finished_jobs: true", report
      assert_match "clear_finished_jobs_after: 1 day (86400s)", report
      assert_match "## Queue database", report
      assert_match "## Registered processes", report
      assert_match "worker-1", report
      assert_match "queues=reports,mailers", report
      assert_match "## Queues", report
      assert_match(/reports\s+capacity=5/, report)
      assert_match "dead=1", report
    end

    test "says what the panel is complaining about" do
      SolidQueue::Queue.find_by_name("reports").pause

      assert_match(/warning: 1 queue paused/, SettingsReport.new.to_s)
    end

    test "carries the configuration files as they are written" do
      report = SettingsReport.new.to_s

      assert_match "## config/queue.yml", report
      assert_match "polling_interval: 0.1", report
      assert_match "## config/recurring.yml", report
    end

    test "never carries the credentials" do
      SolidQueuePanel.configuration.username = "admin"
      SolidQueuePanel.configuration.password = "a-very-long-password"

      report = SettingsReport.new.to_s

      assert_no_match(/a-very-long-password/, report)
      assert_no_match(/^username/, report)
    ensure
      SolidQueuePanel.configuration.username = nil
      SolidQueuePanel.configuration.password = nil
    end

    test "includes the machines and the heaviest jobs once they are recorded" do
      ProcessSample.create!(name: "worker-1", kind: "Worker", hostname: "jobs-01", pid: 1, rss_kb: 250_000,
                            cpu_percent: 30.0, threads: 9, cpu_count: 4, load_average: 2.0,
                            memory_kb: 8_000_000, available_memory_kb: 4_000_000, created_at: Time.current)
      JobUsage.create!(class_name: "ReportJob", bucket_at: JobUsage.bucket_for(Time.current),
                       executions: 10, cpu_ms: 5_000, wall_ms: 9_000, max_rss_kb: 260_000)

      report = SettingsReport.new.to_s

      assert_match "## Machine jobs-01", report
      assert_match "cores=4", report
      assert_match "advice:", report
      assert_match "## Heaviest job classes", report
      assert_match(/ReportJob\s+runs=10/, report)
    end

    test "leaves out what has not been recorded" do
      report = SettingsReport.new.to_s

      assert_no_match(/## Machine/, report)
      assert_no_match(/## Heaviest job classes/, report)
    end
  end
end
