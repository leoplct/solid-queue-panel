# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class TuningAdviceTest < TestCase
    test "says how many more workers the memory can hold" do
      advice = advice_for(worker_rss_kb: 250_000, memory_kb: 8_000_000, available_memory_kb: 5_000_000, workers: 2)

      assert_equal 17, advice.affordable_processes
      assert_match "Each worker holds 244 MB", advice.statements.first.text
      assert_match "room for about 17 worker processes", advice.statements.first.text
    end

    test "warns when the machine is nearly out of memory" do
      advice = advice_for(worker_rss_kb: 500_000, memory_kb: 4_000_000, available_memory_kb: 200_000, workers: 4)

      statement = advice.statements.first

      assert_equal :warning, statement.level
      assert_match "no room left", statement.text
    end

    test "warns when the CPU is saturated and suggests fewer threads" do
      advice = advice_for(load_average: 6.0, cpu_count: 4, threads: 5)

      cpu = advice.statements.find { |statement| statement.text.include?("Load average") }

      assert_equal :warning, cpu.level
      assert_match "CPU is the bottleneck", cpu.text
      assert_equal 4, advice.suggested_threads
    end

    test "suggests more threads when the machine is idle" do
      advice = advice_for(load_average: 0.4, cpu_count: 4, threads: 5)

      assert_match "mostly idle", advice.statements.find { |statement| statement.text.include?("Load average") }.text
      assert_equal 7, advice.suggested_threads
    end

    test "never suggests more processes than there are cores" do
      advice = advice_for(worker_rss_kb: 50_000, memory_kb: 16_000_000, available_memory_kb: 12_000_000, cpu_count: 2)

      assert_operator advice.affordable_processes, :>, 2
      assert_equal 2, advice.suggested_processes
    end

    test "warns when the database pool is smaller than the thread pool" do
      advice = advice_for(threads: 50)

      pool = advice.statements.find { |statement| statement.text.include?("database pool") }

      assert_equal :warning, pool.level
      assert_match "at least 51", pool.text
    end

    private
      def advice_for(worker_rss_kb: 200_000, memory_kb: 8_000_000, available_memory_kb: 4_000_000,
                     cpu_count: 4, load_average: 2.0, workers: 1, threads: 5, hostname: "jobs-01")
        samples = workers.times.map do |index|
          ProcessSample.new(
            name: "worker-#{index + 1}", kind: "Worker", hostname: hostname, pid: index, rss_kb: worker_rss_kb,
            cpu_percent: 30.0, threads: threads, cpu_count: cpu_count, load_average: load_average,
            memory_kb: memory_kb, available_memory_kb: available_memory_kb, created_at: Time.current
          )
        end

        thread_pools = samples.to_h { |sample| [ sample.name, threads ] }

        TuningAdvice.new(ResourceReport::Host.new(hostname: hostname, samples: samples, thread_pools: thread_pools))
      end
  end
end
