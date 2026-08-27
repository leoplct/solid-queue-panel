# frozen_string_literal: true

# Builds jobs in each of the states Solid Queue can put them in. Jobs are
# created through Solid Queue itself, so the execution rows are the ones the
# real system would have written.
module JobFactory
  def reset_solid_queue
    SolidQueue::Job.delete_all
    SolidQueue::ReadyExecution.delete_all
    SolidQueue::ScheduledExecution.delete_all
    SolidQueue::ClaimedExecution.delete_all
    SolidQueue::BlockedExecution.delete_all
    SolidQueue::FailedExecution.delete_all
    SolidQueue::RecurringExecution.delete_all
    SolidQueue::RecurringTask.delete_all
    SolidQueue::Process.delete_all
    SolidQueue::Pause.delete_all
  end

  def create_job(class_name: "ReportJob", queue_name: "default", status: :queued, scheduled_at: nil, arguments: [ 42 ])
    job = SolidQueue::Job.create!(
      class_name: class_name,
      queue_name: queue_name,
      active_job_id: SecureRandom.uuid,
      scheduled_at: scheduled_at || (status == :scheduled ? 1.hour.from_now : Time.current),
      concurrency_key: ("#{class_name}/1" if status == :blocked),
      arguments: { "job_class" => class_name, "job_id" => SecureRandom.uuid, "arguments" => arguments, "executions" => 0 }
    )

    case status
    when :queued, :scheduled then job
    when :in_progress then claim(job)
    when :failed then fail_job(job)
    when :finished then finish(job)
    when :blocked then block(job)
    else job
    end
  end

  def create_process(kind: "Worker", name: "worker-1", supervisor: nil, metadata: { "queues" => "*", "thread_pool_size" => 5, "polling_interval" => 0.1 })
    SolidQueue::Process.create!(
      kind: kind,
      name: name,
      pid: rand(1000..9999),
      hostname: "dummy-host",
      supervisor: supervisor,
      last_heartbeat_at: Time.current,
      metadata: metadata
    )
  end

  private
    def claim(job, process: nil)
      job.ready_execution&.destroy!
      SolidQueue::ClaimedExecution.create!(job: job, process: process || create_process(name: "worker-#{job.id}"))
      job.reload
    end

    def fail_job(job, message: "Something went wrong")
      job.ready_execution&.destroy!
      SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "RuntimeError", message: message, backtrace: [ "app/jobs/report_job.rb:12" ] })
      job.reload
    end

    def finish(job)
      job.ready_execution&.destroy!
      job.update!(finished_at: Time.current)
      job
    end

    def block(job)
      job.ready_execution&.destroy!
      SolidQueue::BlockedExecution.create!(job: job)
      job.reload
    end
end
