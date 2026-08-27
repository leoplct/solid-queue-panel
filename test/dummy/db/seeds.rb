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
      "executions" => rand(0..3)
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
