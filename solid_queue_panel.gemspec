# frozen_string_literal: true

require_relative "lib/solid_queue_panel/version"

Gem::Specification.new do |spec|
  spec.name = "solid_queue_panel"
  spec.version = SolidQueuePanel::VERSION
  spec.authors = [ "Leonardo Pellicciotta" ]
  spec.email = [ "1176145+leoplct@users.noreply.github.com" ]

  spec.summary = "A web dashboard for Solid Queue, in the spirit of the Sidekiq web UI"
  spec.description = <<~DESCRIPTION.strip
    A mountable Rails engine that gives Solid Queue the web UI Sidekiq users are used to:
    live process and queue monitoring, job browsing and retrying, recurring tasks,
    per class metrics and a read-only view of the whole Solid Queue configuration.
    Styled with Tailwind CSS, ships precompiled assets and has no runtime dependency
    beyond Rails and Solid Queue.
  DESCRIPTION

  spec.homepage = "https://github.com/leoplct/solid-queue-panel"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "lib/**/*",
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md"
  ]

  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 7.2"
  spec.add_dependency "solid_queue", ">= 1.0"
end
