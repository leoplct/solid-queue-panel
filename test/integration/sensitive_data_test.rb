# frozen_string_literal: true

require "test_helper"

# The panel shows Active Job payloads, which is the one place it puts data the
# application owns in front of whoever is watching the queue.
class SensitiveDataTest < SolidQueuePanel::IntegrationTestCase
  setup do
    @job = create_job(
      status: :queued,
      class_name: "WelcomeJob",
      arguments: [ 42, { "email" => "patient@example.com", "plan" => "pro" } ]
    )
  end

  teardown { SolidQueuePanel.configuration.hide_job_arguments = false }

  test "the job page filters the keys the application filters out of its logs" do
    get panel.job_path(@job)

    assert_response :success
    assert_no_match "patient@example.com", payload_shown
    assert_match "[FILTERED]", payload_shown
    assert_match "pro", payload_shown, "only the filtered keys go, not the whole payload"
    assert_match "42", payload_shown
  end

  test "the jobs list filters arguments too" do
    get panel.jobs_path

    assert_response :success
    assert_no_match "patient@example.com", response.body
  end

  test "hide_job_arguments shows no arguments at all" do
    SolidQueuePanel.configuration.hide_job_arguments = true

    get panel.job_path(@job)

    assert_response :success
    assert_equal SolidQueuePanel::PayloadFilter::HIDDEN, payload_shown.strip
  end

  private
    # The payload is the last <pre> on a job page: reading it rather than the
    # whole document keeps these assertions from passing on some unrelated word
    # in the navigation.
    def payload_shown
      css_select("pre").last.text
    end
end
