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

  # The resource metrics tables are optional, so every page has to work without
  # them. Reported from a PostgreSQL application where the dashboard raised
  # PG::UndefinedTable on solid_queue_panel_job_usages.
  test "every page works when the resource metrics tables were never installed" do
    create_process(metadata: { "queues" => "*", "thread_pool_size" => 5 })

    without_resource_metrics_tables do
      [ panel.root_path, panel.jobs_path, panel.queues_path, panel.processes_path,
        panel.metrics_path, panel.resources_path, panel.settings_path ].each do |path|
        get path

        assert_response :success, "#{path} should render without the resource metrics tables"
      end
    end
  end

  test "the settings report is built without the resource metrics tables" do
    without_resource_metrics_tables do
      get panel.report_settings_path

      assert_response :success
    end
  end

  # The Finished counter on the dashboard covers 24 hours, while the finished
  # list is not bounded in time. Showing the first next to the second said "0"
  # over a page listing nineteen jobs, so that tab carries no counter.
  test "the finished tab shows no counter, since its list is not bounded in time" do
    # One from the setup, plus one old enough that a 24 hour counter misses it.
    create_job(status: :finished).update_columns(finished_at: 40.days.ago)

    get panel.jobs_path(status: "finished")

    assert_response :success
    assert_select "a", text: /Finished\s*\d/, count: 0, message: "the tab must not carry a count its list does not match"
    assert_select "h2", text: /Finished\s*\(2\)/, message: "the heading counts both, including the old one"
  end

  test "dashboard shows the capacity of every queue" do
    create_process(metadata: { "queues" => "*", "thread_pool_size" => 5 })

    get panel.root_path

    assert_response :success
    assert_select "h2", text: /Capacity/
    assert_select "a", text: "reports"
    assert_select "svg[aria-label*=?]", "enqueued", minimum: 2, message: "each queue gets a sparkline"

    %w[Pending Blocked Scheduled Retries Dead].each do |state|
      assert_select "th", text: /#{state}/, message: "#{state} should have a column"
    end
    assert_select "th", text: /Finished/
  end

  test "dashboard lists the jobs being processed right now" do
    get panel.root_path

    assert_response :success
    assert_select "h2", text: /Processing/
    assert_select "a[href=?]", panel.job_path(@in_progress)
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

  test "each list that can be put back to work has a button for it" do
    { "failed" => "Retry all", "scheduled" => "Run all now", "blocked" => "Release all" }.each do |status, label|
      get panel.jobs_path(status: status)

      assert_response :success
      assert_select "form[action=?]", panel.run_all_jobs_path(status: status)
      assert_match label, response.body
    end
  end

  test "lists with nothing to run have no button" do
    %w[queued in_progress finished].each do |status|
      get panel.jobs_path(status: status)

      assert_response :success
      assert_select "form[action=?]", panel.run_all_jobs_path(status: status), count: 0
    end
  end

  test "the remove duplicates button only shows on the queued tab" do
    get panel.jobs_path(status: "queued")

    assert_response :success
    assert_select "a[href=?]", panel.duplicates_jobs_path

    get panel.jobs_path(status: "failed")

    assert_response :success
    assert_select "a[href=?]", panel.duplicates_jobs_path, count: 0
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

  test "the settings page can be copied as plain text" do
    get panel.settings_path

    assert_response :success
    assert_select "button[data-sqp-copy=?]", panel.report_settings_path

    get panel.report_settings_path

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match "# Solid Queue report", response.body
    assert_match "## Queues", response.body
  end

  test "assets are served from the gem" do
    get panel.panel_asset_path(digest: SolidQueuePanel::AssetsController.digest("solid_queue_panel.css"), file: "solid_queue_panel.css")

    assert_response :success
    assert_equal "text/css", response.media_type

    get panel.panel_asset_path(digest: SolidQueuePanel::AssetsController.digest("solid_queue_panel.js"), file: "solid_queue_panel.js")

    assert_response :success
  end

  test "unknown assets are not found" do
    get panel.panel_asset_path(digest: "whatever", file: "secrets.txt")

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
