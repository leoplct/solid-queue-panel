# frozen_string_literal: true

module SolidQueuePanel
  # Turns the query string of the jobs page into a Solid Queue relation. Each
  # status maps to the execution table that holds jobs in that state, which is
  # also the table that dictates the natural order of the list: ready jobs are
  # listed the way workers will pick them up, scheduled jobs by their due date,
  # failed jobs newest first.
  class JobsQuery
    DEFAULT_STATUS = "all"
    STATUSES = ([ DEFAULT_STATUS ] + JobStatus::ALL.map(&:to_s)).freeze
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    DIGITS = /\A\d+\z/

    attr_reader :status, :queue_name, :search

    def initialize(status: nil, queue_name: nil, search: nil)
      @status = STATUSES.include?(status.to_s) ? status.to_s : DEFAULT_STATUS
      @queue_name = queue_name.presence
      @search = search.presence&.strip
    end

    def scope
      @scope ||= searched(filtered(ordered(base)))
    end

    def count
      @count ||= scope.count
    end

    def page(pagination)
      scope.offset(pagination.offset).limit(pagination.per_page).preload(preloads)
    end

    def filtered?
      queue_name.present? || search.present?
    end

    def to_params
      { status: status, queue_name: queue_name, search: search }.compact_blank
    end

    private
      def base
        case status
        when "in_progress" then SolidQueue::Job.joins(:claimed_execution)
        when "queued" then SolidQueue::Job.joins(:ready_execution)
        when "blocked" then SolidQueue::Job.joins(:blocked_execution)
        when "scheduled" then SolidQueue::Job.joins(:scheduled_execution)
        when "failed" then SolidQueue::Job.joins(:failed_execution)
        when "finished" then SolidQueue::Job.finished
        else SolidQueue::Job.all
        end
      end

      def ordered(relation)
        case status
        when "in_progress" then relation.order(SolidQueue::ClaimedExecution.arel_table[:created_at].asc)
        when "queued", "blocked" then relation.order(priority: :asc, id: :asc)
        when "scheduled" then relation.order(SolidQueue::ScheduledExecution.arel_table[:scheduled_at].asc)
        when "failed" then relation.order(SolidQueue::FailedExecution.arel_table[:created_at].desc)
        when "finished" then relation.order(finished_at: :desc)
        else relation.order(id: :desc)
        end
      end

      def filtered(relation)
        queue_name.present? ? relation.where(queue_name: queue_name) : relation
      end

      def searched(relation)
        case search
        when nil then relation
        when DIGITS then relation.where(id: search)
        when UUID then relation.where(active_job_id: search)
        else relation.where(SolidQueue::Job.arel_table[:class_name].matches("%#{sanitize_like(search)}%"))
        end
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value)
      end

      def preloads
        [ :ready_execution, :scheduled_execution, :blocked_execution, :failed_execution, { claimed_execution: :process } ]
      end
  end
end
