# frozen_string_literal: true

require "test_helper"

class PagesTest < SolidQueuePanel::IntegrationTestCase
  setup do
    @queued = create_job(status: :queued, queue_name: "default")
    @scheduled = create_job(status: :scheduled, queue_name: "reports")
    @failed = create_job(status: :failed, class_name: "BrokenJob")
    @finished = create_job(status: :finished)
    @blocked = create_job(status: :blocked)
    @in_progress = create_job(status: :in_progress)
    @task = SolidQueue::RecurringTask.create!(key: "cleanup", schedule: "every hour", class_name: "CleanupJob", static: true)
  end

  test "dashboard shows the capacity of every queue" do
    create_process(metadata: { "queues" => "*", "thread_pool_size" => 5 })

    get panel.root_path

    assert_response :success
    assert_select "h2", text: /Capacity/
    assert_select "a", text: "reports"
    assert_select "a", text: /BrokenJob/
  end

  test "metrics page charts the throughput" do
    get panel.metrics_path

    assert_response :success
    assert_select "h2", text: /Throughput/
  end

  test "resources page explains how to install the metrics when they are missing" do
    without_resource_metrics do
      get panel.resources_path

      assert_response :success
      assert_match "solid_queue_panel:resource_metrics", response.body
    end
  end

  test "resources page waits for the first reading once the tables are there" do
    SolidQueuePanel::ProcessSample.delete_all

    get panel.resources_path

    assert_response :success
    assert_match "No reading yet", response.body
  end

  test "the dashboard works without the resource metrics" do
    without_resource_metrics do
      get panel.root_path

      assert_response :success
      assert_select "h2", text: /Capacity/
    end
  end

  test "resources page shows what each machine is using" do
    SolidQueuePanel::ProcessSample.create!(
      name: "worker-1", kind: "Worker", hostname: "jobs-01", pid: 42, rss_kb: 250_000, cpu_percent: 40.0,
      threads: 9, cpu_count: 4, load_average: 2.0, memory_kb: 8_000_000, available_memory_kb: 4_000_000,
      created_at: Time.current
    )
    SolidQueuePanel::JobUsage.create!(class_name: "ReportJob", bucket_at: SolidQueuePanel::JobUsage.bucket_for(Time.current),
                                      executions: 10, cpu_ms: 5_000, wall_ms: 9_000, memory_growth_kb: 2_000, max_rss_kb: 260_000)

    get panel.resources_path

    assert_response :success
    assert_select "h2", text: /jobs-01/
    assert_match "ReportJob", response.body
  end

  test "jobs page lists jobs and filters by status" do
    get panel.jobs_path

    assert_response :success
    assert_select "a", text: "ReportJob"

    get panel.jobs_path(status: "failed")

    assert_response :success
    assert_select "a", text: "BrokenJob"
    assert_select "a", text: "ReportJob", count: 0
  end

  test "the remove duplicates button only shows on the queued tab" do
    get panel.jobs_path(status: "queued")

    assert_response :success
    assert_select "form[action=?]", panel.remove_duplicates_jobs_path(status: "queued")

    get panel.jobs_path(status: "failed")

    assert_response :success
    assert_select "form[action=?]", panel.remove_duplicates_jobs_path(status: "failed"), count: 0
  end

  test "jobs page filters by search term" do
    get panel.jobs_path(search: "Broken")

    assert_response :success
    assert_select "a", text: "BrokenJob"
    assert_select "a", text: "ReportJob", count: 0
  end

  test "job page shows the error of a failed job" do
    get panel.job_path(@failed)

    assert_response :success
    assert_select "h1", text: "BrokenJob"
    assert_match "Something went wrong", response.body
  end

  test "queues page lists every queue" do
    get panel.queues_path

    assert_response :success
    assert_select "a", text: "default"
    assert_select "a", text: "reports"
  end

  test "queue page lists the jobs of that queue only" do
    get panel.queue_path("reports")

    assert_response :success
    assert_select "h1", text: "reports"

    get panel.queue_path("reports", status: "scheduled")

    assert_response :success
    assert_select "a[href=?]", panel.job_path(@scheduled)
    assert_select "a[href=?]", panel.job_path(@queued), count: 0
  end

  test "processes page lists registered processes" do
    supervisor = create_process(kind: "Supervisor", name: "supervisor-1", metadata: {})
    create_process(kind: "Worker", name: "worker-42", supervisor: supervisor)

    get panel.processes_path

    assert_response :success
    assert_select "a", text: "supervisor-1"
    assert_select "a", text: "worker-42"
  end

  test "process page shows metadata and running jobs" do
    process = SolidQueue::ClaimedExecution.first.process

    get panel.process_path(process)

    assert_response :success
    assert_select "h1", text: process.name
  end

  test "recurring tasks page lists tasks" do
    get panel.recurring_tasks_path

    assert_response :success
    assert_select "a", text: "cleanup"

    get panel.recurring_task_path(@task.key)

    assert_response :success
    assert_select "h1", text: "cleanup"
  end

  test "metrics page aggregates jobs per class" do
    get panel.metrics_path

    assert_response :success
    assert_select "a", text: "ReportJob"
  end

  test "settings page shows the Solid Queue configuration" do
    get panel.settings_path

    assert_response :success
    assert_match "preserve_finished_jobs", response.body
    assert_match "config/queue.yml", response.body
  end

  test "assets are served from the gem" do
    get panel.panel_asset_path(version: SolidQueuePanel::VERSION, file: "solid_queue_panel.css")

    assert_response :success
    assert_equal "text/css", response.media_type

    get panel.panel_asset_path(version: SolidQueuePanel::VERSION, file: "solid_queue_panel.js")

    assert_response :success
  end

  test "unknown assets are not found" do
    get panel.panel_asset_path(version: SolidQueuePanel::VERSION, file: "secrets.txt")

    assert_response :not_found
  end

  test "empty installation renders without errors" do
    reset_solid_queue

    get panel.root_path
    assert_response :success

    get panel.jobs_path
    assert_response :success

    get panel.queues_path
    assert_response :success

    get panel.processes_path
    assert_response :success
  end
end
