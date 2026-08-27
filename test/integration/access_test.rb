# frozen_string_literal: true

require "test_helper"

class AccessTest < SolidQueuePanel::IntegrationTestCase
  test "read-only mode hides destructive controls" do
    create_job(status: :failed)
    SolidQueuePanel.configuration.read_only = true

    get panel.jobs_path(status: "failed")

    assert_response :success
    assert_select "form[action=?]", panel.bulk_jobs_path, count: 0
    assert_match "Read only", response.body
  end

  test "read-only mode refuses destructive requests" do
    job = create_job(status: :failed)
    SolidQueuePanel.configuration.read_only = true

    post panel.retry_job_path(job)

    assert_redirected_to panel.root_path
    assert_equal "The panel is running in read-only mode.", flash[:alert]
    assert job.reload.failed_execution.present?
  end

  test "read-only mode refuses to remove duplicates" do
    2.times { create_job(arguments: [ 1 ]) }
    SolidQueuePanel.configuration.read_only = true

    post panel.remove_duplicates_jobs_path(status: "queued")

    assert_equal 2, SolidQueue::Job.count
  end

  test "read-only mode refuses to run everything again" do
    job = create_job(status: :failed)
    SolidQueuePanel.configuration.read_only = true

    post panel.run_all_jobs_path(status: "failed")

    assert job.reload.failed_execution.present?
  end

  test "read-only mode does not even count them" do
    SolidQueuePanel.configuration.read_only = true

    get panel.duplicates_jobs_path

    assert_redirected_to panel.root_path
  end

  test "the theme is stored in a cookie" do
    patch panel.theme_path, params: { theme: "dark" }

    assert_equal "dark", cookies[:solid_queue_panel_theme]

    get panel.root_path
    assert_select "html[data-theme=dark]"

    patch panel.theme_path, params: { theme: "system" }
    assert_predicate cookies[:solid_queue_panel_theme], :blank?
  end

  test "no sign in is required when no credentials are configured" do
    get panel.root_path

    assert_response :success
  end

  test "the sign in page is not reachable when no credentials are configured" do
    get panel.login_path

    assert_redirected_to panel.root_path
  end
end

class SignInTest < SolidQueuePanel::IntegrationTestCase
  setup do
    SolidQueuePanel.configuration.username = "admin"
    SolidQueuePanel.configuration.password = "a-very-long-password"
  end

  test "an anonymous visitor is sent to the sign in page" do
    get panel.queues_path

    assert_redirected_to panel.login_path(return_to: panel.queues_path)
    assert_select "form", count: 0
  end

  test "signing in with the configured credentials" do
    sign_in_as "admin", "a-very-long-password"

    assert_redirected_to panel.root_path
    follow_redirect!
    assert_response :success

    get panel.queues_path
    assert_response :success
  end

  test "signing in returns to the page that was asked for" do
    sign_in_as "admin", "a-very-long-password", return_to: panel.queues_path

    assert_redirected_to panel.queues_path
  end

  test "an off-site return path is ignored" do
    sign_in_as "admin", "a-very-long-password", return_to: "https://example.com/phishing"

    assert_redirected_to panel.root_path
  end

  test "wrong credentials are refused" do
    sign_in_as "admin", "wrong"

    assert_response :unauthorized
    assert_match "Wrong username or password", response.body

    get panel.root_path
    assert_redirected_to panel.login_path(return_to: panel.root_path)
  end

  test "signing out" do
    sign_in_as "admin", "a-very-long-password"

    delete panel.logout_path
    assert_redirected_to panel.login_path

    get panel.root_path
    assert_redirected_to panel.login_path(return_to: panel.root_path)
  end

  test "changing the password signs everybody out" do
    sign_in_as "admin", "a-very-long-password"
    SolidQueuePanel.configuration.password = "another-very-long-password"

    get panel.root_path

    assert_redirected_to panel.login_path(return_to: panel.root_path)
  end

  test "HTTP basic credentials are accepted too" do
    get panel.root_path, headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "a-very-long-password") }

    assert_response :success
  end

  test "a live refresh of an expired session is unauthorized rather than redirected" do
    get panel.root_path, headers: { "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }

    assert_response :unauthorized
  end

  private
    def sign_in_as(username, password, return_to: nil)
      post panel.login_path, params: { username: username, password: password, return_to: return_to }.compact
    end
end
