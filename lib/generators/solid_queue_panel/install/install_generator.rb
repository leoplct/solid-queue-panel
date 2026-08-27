# frozen_string_literal: true

require "rails/generators/base"
require "securerandom"

module SolidQueuePanel
  module Generators
    # Sets the panel up in one command: an initializer with generated
    # credentials, the password stored in the encrypted credentials, and the
    # engine mounted in config/routes.rb.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Mounts Solid Queue Panel and generates the credentials to sign in with."

      class_option :at, type: :string, default: "/jobs", desc: "Path to mount the panel at"
      class_option :username, type: :string, default: "admin", desc: "Username to sign in with"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/solid_queue_panel.rb"
      end

      def store_password_in_credentials
        credentials = Rails.application.credentials

        if credentials.key.blank?
          @password_stored = false
          return say_status :skip, "no master key: set SOLID_QUEUE_PANEL_PASSWORD instead", :yellow
        end

        if credentials.read.to_s.match?(/^solid_queue_panel:/)
          @password_stored = false
          return say_status :skip, "credentials already have a solid_queue_panel entry", :yellow
        end

        credentials.write([ credentials.read.to_s.chomp, "", "solid_queue_panel:", "  password: #{password}", "" ].join("\n"))
        @password_stored = true
        say_status :credentials, "stored solid_queue_panel.password"
      rescue StandardError => error
        @password_stored = false
        say_status :skip, "could not write the credentials (#{error.class}): set SOLID_QUEUE_PANEL_PASSWORD instead", :yellow
      end

      def mount_engine
        route %(mount SolidQueuePanel::Engine => "#{options[:at]}")
      end

      def print_credentials
        say ""
        say "Solid Queue Panel is mounted at #{options[:at]}", :green
        say ""
        say "  Username: #{username}"
        say "  Password: #{password}"
        say ""

        if @password_stored
          say "The password is stored in your encrypted credentials. Write it down: this is the"
          say "only time it is printed."
        else
          say "Set it in the environment of every process that serves the panel:"
          say ""
          say "  SOLID_QUEUE_PANEL_PASSWORD=#{password}"
        end

        say ""
      end

      private
        def username
          options[:username]
        end

        def password
          @password ||= SecureRandom.alphanumeric(24)
        end
    end
  end
end
