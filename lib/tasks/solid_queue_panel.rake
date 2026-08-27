# frozen_string_literal: true

namespace :solid_queue_panel do
  desc "Generate a new random password for the Solid Queue Panel sign in"
  task :password do
    require "securerandom"

    password = SecureRandom.alphanumeric(24)

    puts
    puts "  Password: #{password}"
    puts
    puts "  Store it in your encrypted credentials:"
    puts
    puts "    solid_queue_panel:"
    puts "      password: #{password}"
    puts
    puts "  or in the environment of every process that serves the panel:"
    puts
    puts "    SOLID_QUEUE_PANEL_PASSWORD=#{password}"
    puts
  end
end
