# frozen_string_literal: true

class CreateSolidQueuePanelResourceMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_queue_panel_process_samples do |t|
      t.bigint :process_id
      t.string :name, null: false
      t.string :kind, null: false
      t.string :hostname, null: false
      t.integer :pid, null: false

      t.bigint :rss_kb, null: false
      t.float :cpu_percent, null: false, default: 0.0
      t.integer :threads

      t.integer :cpu_count
      t.float :load_average
      t.bigint :memory_kb
      t.bigint :available_memory_kb

      t.datetime :created_at, null: false

      t.index :created_at
      t.index [ :hostname, :created_at ]
      t.index [ :name, :created_at ]
    end

    create_table :solid_queue_panel_job_usages do |t|
      t.string :class_name, null: false
      # Empty for the total of the class, a fingerprint of the arguments for the
      # rows that describe one particular set of them.
      t.string :arguments_fingerprint, null: false, default: ""
      t.datetime :bucket_at, null: false

      t.integer :executions, null: false, default: 0
      t.integer :failures, null: false, default: 0
      t.bigint :cpu_ms, null: false, default: 0
      t.bigint :wall_ms, null: false, default: 0
      t.bigint :memory_growth_kb, null: false, default: 0
      t.bigint :max_rss_kb, null: false, default: 0

      t.timestamps

      t.index [ :class_name, :arguments_fingerprint, :bucket_at ], unique: true, name: "index_solid_queue_panel_job_usages_uniqueness"
      t.index :bucket_at
    end
  end
end
