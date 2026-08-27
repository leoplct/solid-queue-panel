# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class PaginationTest < TestCase
    test "computes offsets and boundaries" do
      pagination = Pagination.new(page: 2, per_page: 25, total_count: 60)

      assert_equal 25, pagination.offset
      assert_equal 3, pagination.total_pages
      assert_equal 26, pagination.first_item
      assert_equal 50, pagination.last_item
      assert_equal 1, pagination.previous_page
      assert_equal 3, pagination.next_page
    end

    test "clamps out of range pages" do
      assert_equal 3, Pagination.new(page: 99, per_page: 10, total_count: 25).page
      assert_equal 1, Pagination.new(page: 0, per_page: 10, total_count: 25).page
      assert_equal 1, Pagination.new(page: nil, per_page: 10, total_count: 0).page
    end

    test "handles an empty collection" do
      pagination = Pagination.new(page: 1, per_page: 25, total_count: 0)

      assert_equal 0, pagination.first_item
      assert_equal 0, pagination.last_item
      assert_not pagination.many_pages?
    end
  end
end
