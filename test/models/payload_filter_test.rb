# frozen_string_literal: true

require "test_helper"

module SolidQueuePanel
  class PayloadFilterTest < TestCase
    test "replaces the values of filtered keys inside a payload" do
      filter = PayloadFilter.new([ :password, :email ])

      filtered = filter.payload("job_class" => "SyncJob", "password" => "hunter2", "email" => "a@b.c")

      assert_equal "SyncJob", filtered["job_class"]
      assert_equal "[FILTERED]", filtered["password"]
      assert_equal "[FILTERED]", filtered["email"]
    end

    test "reaches keys nested in the positional arguments" do
      filter = PayloadFilter.new([ :token ])

      filtered = filter.payload("arguments" => [ 42, { "token" => "secret", "keep" => "visible" } ])

      assert_equal 42, filtered["arguments"].first
      assert_equal "[FILTERED]", filtered["arguments"].last["token"]
      assert_equal "visible", filtered["arguments"].last["keep"]
    end

    test "filters a bare list of arguments" do
      filter = PayloadFilter.new([ :ssn ])

      assert_equal [ { "ssn" => "[FILTERED]" } ], filter.arguments([ { "ssn" => "123-45-6789" } ])
    end

    test "leaves everything alone when nothing is configured" do
      filter = PayloadFilter.new([])

      assert_equal({ "email" => "a@b.c" }, filter.payload("email" => "a@b.c"))
    end

    test "a positional argument cannot be filtered by key, and is not pretended to be" do
      filter = PayloadFilter.new([ :email ])

      assert_equal [ "a@b.c" ], filter.arguments([ "a@b.c" ])
    end

    test "hides everything when hide_job_arguments is set" do
      filter = PayloadFilter.new([], hidden: true)

      assert_equal PayloadFilter::HIDDEN, filter.payload("arguments" => [ 1 ])
      assert_nil filter.arguments([ 1 ])
    end

    test "defaults to what the application filters out of its own logs" do
      filter = PayloadFilter.new

      assert_equal "[FILTERED]", filter.payload("passw" => "hunter2")["passw"]
    end
  end
end
