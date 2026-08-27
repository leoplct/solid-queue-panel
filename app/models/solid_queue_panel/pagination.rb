# frozen_string_literal: true

module SolidQueuePanel
  # Minimal offset pagination. Keeping it in-house avoids forcing a pagination
  # gem (and a specific version of it) on the host application.
  class Pagination
    attr_reader :page, :per_page, :total_count

    def initialize(page:, per_page:, total_count:)
      @per_page = [ per_page.to_i, 1 ].max
      @total_count = total_count.to_i
      @page = page.to_i.clamp(1, [ total_pages, 1 ].max)
    end

    def offset
      (page - 1) * per_page
    end

    def total_pages
      (total_count.to_f / per_page).ceil
    end

    def first_item
      total_count.zero? ? 0 : offset + 1
    end

    def last_item
      [ offset + per_page, total_count ].min
    end

    def previous_page
      page - 1 if page > 1
    end

    def next_page
      page + 1 if page < total_pages
    end

    def many_pages?
      total_pages > 1
    end
  end
end
