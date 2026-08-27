# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class QueueCapacityTest < TestCase
    test "capacity is the number of threads polling each queue" do
      create_process(name: "worker-1", metadata: { "queues" => "default,reports", "thread_pool_size" => 5 })
      create_process(name: "worker-2", metadata: { "queues" => "reports", "thread_pool_size" => 3 })
      create_job(queue_name: "default")
      create_job(queue_name: "reports")

      rows = QueueCapacity.new.rows.index_by(&:name)

      assert_equal 5, rows["default"].capacity
      assert_equal 8, rows["reports"].capacity
      assert_equal 8, QueueCapacity.new.total_capacity
    end

    test "a wildcard worker lends its threads to every queue" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 4 })
      create_job(queue_name: "anything")

      assert_equal 4, QueueCapacity.new.rows.first.capacity
    end

    test "a prefixed wildcard only covers the queues it names" do
      create_process(metadata: { "queues" => "mail*", "thread_pool_size" => 2 })
      create_job(queue_name: "mailers")
      create_job(queue_name: "reports")

      rows = QueueCapacity.new.rows.index_by(&:name)

      assert_equal 2, rows["mailers"].capacity
      assert_equal 0, rows["reports"].capacity
    end

    test "counts what is running and what is waiting" do
      worker = create_process(metadata: { "queues" => "*", "thread_pool_size" => 4 })
      2.times { create_job(queue_name: "reports", status: :in_progress, process: worker) }
      3.times { create_job(queue_name: "reports") }
      create_job(queue_name: "reports", status: :scheduled)

      row = QueueCapacity.new.rows.first

      assert_equal 2, row.in_progress
      assert_equal 3, row.pending
      assert_equal 5, row.backlog
      assert_in_delta 50.0, row.utilization, 0.1
    end

    test "every state Solid Queue can put a job in has its own number" do
      worker = create_process(metadata: { "queues" => "*", "thread_pool_size" => 4 })
      create_job(queue_name: "reports")
      create_job(queue_name: "reports", status: :in_progress, process: worker)
      create_job(queue_name: "reports", status: :blocked)
      create_job(queue_name: "reports", status: :scheduled)
      create_job(queue_name: "reports", status: :failed)
      2.times { create_job(queue_name: "reports", status: :finished) }

      row = QueueCapacity.new.rows.first

      assert_equal 1, row.pending, "waiting to be claimed"
      assert_equal 1, row.in_progress, "claimed by a worker"
      assert_equal 1, row.blocked, "held back by a concurrency limit"
      assert_equal 1, row.scheduled, "waiting for its time"
      assert_equal 1, row.dead, "failed and not retried"
      assert_equal 2, row.finished, "finished in the period"
      assert_equal 3, row.waiting, "everything that has not run yet"
      assert_equal 2, row.backlog, "what a worker can pick up now"
    end

    test "separates retries, scheduled jobs and dead ones" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 4 })
      create_job(queue_name: "reports")
      create_job(queue_name: "reports", status: :failed)
      scheduled = create_job(queue_name: "reports", status: :scheduled)
      retried = create_job(queue_name: "reports", status: :scheduled)
      retried.update!(arguments: retried.arguments.merge("executions" => 2))

      row = QueueCapacity.new.rows.first

      assert_equal 1, row.retries
      assert_equal 2, row.scheduled
      assert_equal 1, row.dead
      assert_equal 1, row.pending
      assert_not_nil scheduled
    end

    test "a job that has run before and is back in the queue counts as a retry" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 4 })
      job = create_job(queue_name: "reports")
      job.update!(arguments: job.arguments.merge("executions" => 1))

      assert_equal 1, QueueCapacity.new.rows.first.retries
    end

    test "reports when the queue was last added to" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 1 })
      create_job(queue_name: "reports")
      SolidQueue::ReadyExecution.update_all(created_at: 5.minutes.ago)

      assert_in_delta 5.minutes.ago, QueueCapacity.new.rows.first.last_enqueued_at, 5
    end

    test "the estimate spreads the work over the threads that can pick it up" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 2 })
      4.times { create_job(queue_name: "reports", class_name: "ReportJob") }

      capacity = QueueCapacity.new(durations: FixedDurations.new(3.0))

      assert_in_delta 6.0, capacity.rows.first.eta_seconds, 0.01
    end

    test "jobs nothing is known about make the estimate unknown" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 2 })
      create_job(queue_name: "reports", class_name: "NeverSeenJob")

      row = QueueCapacity.new.rows.first

      assert_predicate row, :unknown_eta?
      assert_nil row.eta_seconds
      assert_equal 1, row.unknown_jobs
    end

    test "an estimate covering only part of the queue is a floor" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 1 })
      create_job(queue_name: "reports", class_name: "ReportJob")
      create_job(queue_name: "reports", class_name: "NeverSeenJob")

      capacity = QueueCapacity.new(durations: PartialDurations.new("ReportJob" => 4.0))
      row = capacity.rows.first

      assert_predicate row, :partial_eta?
      assert_in_delta 4.0, row.eta_seconds, 0.01
      assert_equal 1, row.unknown_jobs
    end

    test "there is no estimate without a worker" do
      create_job(queue_name: "reports")

      row = QueueCapacity.new.rows.first

      assert_equal 0, row.capacity
      assert_nil row.eta_seconds
      assert_not row.workable?
    end

    test "there is no estimate for a paused queue" do
      create_process(metadata: { "queues" => "*", "thread_pool_size" => 2 })
      create_job(queue_name: "reports")
      SolidQueue::Queue.find_by_name("reports").pause

      row = QueueCapacity.new.rows.first

      assert_predicate row, :paused?
      assert_nil row.eta_seconds
    end

    test "an empty queue has nothing to estimate" do
      create_process(metadata: { "queues" => "reports", "thread_pool_size" => 2 })

      row = QueueCapacity.new.rows.first

      assert_predicate row, :idle?
      assert_nil row.eta_seconds
    end

    class PartialDurations
      def initialize(seconds_by_class)
        @seconds_by_class = seconds_by_class
      end

      def average_seconds(class_name)
        @seconds_by_class[class_name]
      end

      def basis
        :measured
      end
    end

    class FixedDurations
      def initialize(seconds)
        @seconds = seconds
      end

      def average_seconds(_class_name)
        @seconds
      end

      def basis
        :measured
      end
    end
  end
end
