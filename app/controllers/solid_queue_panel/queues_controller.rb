# frozen_string_literal: true

module SolidQueuePanel
  class QueuesController < ApplicationController
    before_action :ensure_write_access, only: %i[pause resume clear]
    before_action :set_queue, only: %i[show pause resume clear]

    def index
      @queues = Queues.new.to_a
      @largest_queue = @queues.map { |queue| queue.pending + queue.in_progress }.max.to_i
    end

    def show
      @summary = Queues.new.find_by_name(@queue.name)
      @query = JobsQuery.new(status: params[:status].presence || "queued", queue_name: @queue.name, search: params[:search])
      @pagination = paginate(@query.count)
      @jobs = @query.page(@pagination)
    end

    def pause
      @queue.pause
      audit :pause_queue, queue_name: @queue.name
      redirect_back_with notice: "Queue #{@queue.name} is paused: workers will skip it until it is resumed."
    end

    def resume
      @queue.resume
      audit :resume_queue, queue_name: @queue.name
      redirect_back_with notice: "Queue #{@queue.name} was resumed."
    end

    # Discards every job waiting in the queue. Jobs already claimed by a worker
    # keep running, Solid Queue does not allow interrupting them.
    def clear
      @queue.clear
      audit :clear_queue, queue_name: @queue.name
      redirect_to queues_path, notice: "Queue #{@queue.name} was cleared."
    end

    private
      def set_queue
        @queue = SolidQueue::Queue.find_by_name(params[:name])
      end
  end
end
