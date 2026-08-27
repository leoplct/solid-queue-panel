# frozen_string_literal: true

# Fills the dummy application with a realistic mix of jobs, processes and
# recurring tasks so every page of the dashboard has something to show.

QUEUES = %w[default mailers reports background].freeze
JOB_CLASSES = %w[ReportJob MailerJob CleanupJob BrokenJob ImportJob].freeze

def build_job(class_name: JOB_CLASSES.sample, queue_name: QUEUES.sample, scheduled_at: Time.current, concurrency_key: nil, enqueued_at: nil)
  SolidQueue::Job.create!(
    class_name: class_name,
    queue_name: queue_name,
    active_job_id: SecureRandom.uuid,
    priority: [ 0, 0, 0, 5 ].sample,
    scheduled_at: scheduled_at,
    concurrency_key: concurrency_key,
    arguments: {
      "job_class" => class_name,
      "job_id" => SecureRandom.uuid,
      "queue_name" => queue_name,
      "arguments" => [ rand(1..500), { "force" => [ true, false ].sample } ],
      # Most jobs run on the first attempt; some are retries.
      "executions" => (rand < 0.15 ? rand(1..3) : 0)
    }
  ).tap do |job|
    # Spreading the enqueue times makes the throughput chart look like a real
    # application rather than a fixture loaded all at once.
    if enqueued_at
      job.update_columns(created_at: enqueued_at, updated_at: enqueued_at)
      job.ready_execution&.update_columns(created_at: enqueued_at)
      job.scheduled_execution&.update_columns(created_at: enqueued_at)
    end
  end
end

SolidQueue::Job.delete_all
[ SolidQueue::ReadyExecution, SolidQueue::ScheduledExecution, SolidQueue::ClaimedExecution,
  SolidQueue::BlockedExecution, SolidQueue::FailedExecution, SolidQueue::RecurringExecution,
  SolidQueue::RecurringTask, SolidQueue::Process, SolidQueue::Pause ].each(&:delete_all)

supervisor = SolidQueue::Process.create!(kind: "Supervisor", name: "supervisor-#{SecureRandom.hex(3)}", pid: 1000,
                                         hostname: "jobs-01", last_heartbeat_at: Time.current, metadata: {})

workers = 3.times.map do |index|
  SolidQueue::Process.create!(kind: "Worker", name: "worker-#{index + 1}", pid: 1001 + index, hostname: "jobs-01",
                              supervisor: supervisor, last_heartbeat_at: Time.current,
                              metadata: { "polling_interval" => 0.1, "queues" => QUEUES.join(","), "thread_pool_size" => 5 })
end

SolidQueue::Process.create!(kind: "Dispatcher", name: "dispatcher-1", pid: 1010, hostname: "jobs-01",
                            supervisor: supervisor, last_heartbeat_at: Time.current,
                            metadata: { "polling_interval" => 1, "batch_size" => 500, "concurrency_maintenance_interval" => 600 })

SolidQueue::Process.create!(kind: "Scheduler", name: "scheduler-1", pid: 1011, hostname: "jobs-01",
                            supervisor: supervisor, last_heartbeat_at: Time.current,
                            metadata: { "polling_interval" => 5, "recurring_schedule" => [ "cleanup" ] })

45.times { build_job(enqueued_at: rand(1..45).minutes.ago) }

10.times { build_job(scheduled_at: rand(1..600).minutes.from_now, enqueued_at: rand(1..300).minutes.ago) }

# Jobs sharing a concurrency key: the first one of each group is ready, the
# others are blocked by Solid Queue itself.
2.times do |group|
  3.times { build_job(concurrency_key: "imports/#{group}", class_name: "ImportJob", queue_name: "background", enqueued_at: rand(1..90).minutes.ago) }
end

8.times do
  job = build_job(class_name: "BrokenJob", enqueued_at: rand(30..900).minutes.ago)
  job.ready_execution&.destroy
  SolidQueue::FailedExecution.create!(
    job: job,
    error: {
      exception_class: [ "ActiveRecord::RecordInvalid", "Net::ReadTimeout", "RuntimeError" ].sample,
      message: "Validation failed: Name can't be blank",
      backtrace: 12.times.map { |line| "app/jobs/broken_job.rb:#{line + 3}:in `perform'" }
    }
  )
  job.failed_execution.update_columns(created_at: job.created_at + rand(5..600).seconds)
end

workers.each do |worker|
  rand(1..3).times do
    job = build_job(enqueued_at: rand(2..20).minutes.ago)
    job.ready_execution&.destroy
    SolidQueue::ClaimedExecution.create!(job: job, process: worker, created_at: rand(1..90).seconds.ago)
  end
end

300.times do
  finished_at = rand(24 * 60).minutes.ago
  enqueued_at = finished_at - rand(1..180).seconds
  job = build_job(scheduled_at: enqueued_at, enqueued_at: enqueued_at)
  job.ready_execution&.destroy
  job.update_columns(finished_at: finished_at)
end

SolidQueue::RecurringTask.create!(key: "cleanup", schedule: "every hour", class_name: "CleanupJob",
                                  description: "Removes stale records", static: true, queue_name: "background")
SolidQueue::RecurringTask.create!(key: "daily_report", schedule: "0 6 * * *", class_name: "ReportJob",
                                  description: "Sends the daily report", static: true, queue_name: "reports")

SolidQueue::RecurringTask.find_by(key: "cleanup").then do |task|
  3.times do |index|
    job = build_job(class_name: "CleanupJob", queue_name: "background", enqueued_at: (index + 1).hours.ago)
    SolidQueue::RecurringExecution.create!(job: job, task_key: task.key, run_at: (index + 1).hours.ago)
  end
end

SolidQueue::Queue.find_by_name("mailers").pause

puts "Seeded #{SolidQueue::Job.count} jobs, #{SolidQueue::Process.count} processes."

# Resource metrics, when the tables are installed: a day of samples for every
# process, and the CPU and memory each job class used.
if SolidQueuePanel.resource_metrics?
  SolidQueuePanel::ProcessSample.delete_all
  SolidQueuePanel::JobUsage.delete_all

  HOST = { cpu_count: 4, memory_kb: 8 * 1024 * 1024 }.freeze
  SAMPLE_EVERY = 10.minutes

  processes = SolidQueue::Process.order(:kind, :name).to_a

  samples = (0...(24 * 60 / 10)).flat_map do |step|
    at = (step * SAMPLE_EVERY).ago
    busy = 0.35 + (Math.sin(step / 7.0) + 1) * 0.2
    used_kb = (HOST[:memory_kb] * (0.45 + busy * 0.35)).to_i

    processes.map do |process|
      worker = process.kind == "Worker"

      {
        process_id: process.id,
        name: process.name,
        kind: process.kind,
        hostname: "jobs-01",
        pid: process.pid,
        rss_kb: worker ? (190_000 + (busy * 90_000) + rand(-8_000..8_000)).to_i : (85_000 + rand(-4_000..4_000)),
        cpu_percent: worker ? (busy * 90 + rand(-8..8)).round(2) : rand(1.0..4.0).round(2),
        threads: worker ? 9 : 3,
        cpu_count: HOST[:cpu_count],
        load_average: (HOST[:cpu_count] * busy + rand(-0.3..0.3)).round(2),
        memory_kb: HOST[:memory_kb],
        available_memory_kb: HOST[:memory_kb] - used_kb,
        created_at: at
      }
    end
  end

  SolidQueuePanel::ProcessSample.insert_all(samples)

  usages = JOB_CLASSES.flat_map do |class_name|
    weight = { "ReportJob" => 6.0, "ImportJob" => 3.5, "MailerJob" => 0.6, "CleanupJob" => 1.2, "BrokenJob" => 0.4 }.fetch(class_name, 1.0)

    24.times.map do |hour|
      executions = rand(4..18)

      {
        class_name: class_name,
        bucket_at: SolidQueuePanel::JobUsage.bucket_for(hour.hours.ago),
        executions: executions,
        failures: class_name == "BrokenJob" ? rand(0..2) : 0,
        # Jobs that take tens of seconds to a few minutes, like real background work.
        cpu_ms: (executions * weight * rand(4_000..20_000)).to_i,
        wall_ms: (executions * weight * rand(15_000..60_000)).to_i,
        memory_growth_kb: (executions * weight * rand(200..2_500)).to_i,
        max_rss_kb: (180_000 + weight * rand(5_000..40_000)).to_i,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end

  SolidQueuePanel::JobUsage.insert_all(usages)

  # The jobs being processed right now get a history of their own arguments, and
  # start times spread around it, so the progress bars show a realistic mix.
  averages = SolidQueuePanel::JobUsage.totals.group(:class_name).pluck(
    :class_name, Arel.sql("SUM(wall_ms)"), Arel.sql("SUM(executions)")
  ).to_h { |class_name, wall_ms, executions| [ class_name, wall_ms.to_f / [ executions, 1 ].max ] }

  SolidQueue::ClaimedExecution.includes(:job).each do |execution|
    average_ms = averages.fetch(execution.job.class_name, 5_000)

    executions = rand(3..40)
    expected_ms = average_ms * rand(0.7..1.4)

    SolidQueuePanel::JobUsage.create!(
      class_name: execution.job.class_name,
      arguments_fingerprint: SolidQueuePanel::ArgumentsFingerprint.for(execution.job),
      bucket_at: SolidQueuePanel::JobUsage.bucket_for(1.hour.ago),
      executions: executions,
      cpu_ms: (expected_ms * 0.6 * executions).to_i,
      wall_ms: (expected_ms * executions).to_i,
      memory_growth_kb: rand(500..8_000),
      max_rss_kb: rand(200_000..320_000)
    )

    # Started somewhere between just now and just about to finish, so the bars
    # show the whole range.
    execution.update_columns(created_at: (expected_ms / 1000.0 * rand(0.05..0.95)).seconds.ago)
  end

  puts "Seeded #{SolidQueuePanel::ProcessSample.count} resource samples and #{SolidQueuePanel::JobUsage.count} job usage buckets."
end
