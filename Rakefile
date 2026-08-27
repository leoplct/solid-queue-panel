# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.verbose = false
  task.warning = false
end

TAILWIND_INPUT = "app/assets/stylesheets/solid_queue_panel/application.css"
TAILWIND_OUTPUT = "app/assets/builds/solid_queue_panel.css"

namespace :tailwind do
  desc "Build the Tailwind CSS bundle shipped with the gem"
  task :build do
    sh "bundle exec tailwindcss --input #{TAILWIND_INPUT} --output #{TAILWIND_OUTPUT} --minify"
  end

  desc "Rebuild the Tailwind CSS bundle on every change"
  task :watch do
    sh "bundle exec tailwindcss --input #{TAILWIND_INPUT} --output #{TAILWIND_OUTPUT} --watch"
  end
end

task default: %i[tailwind:build test]
