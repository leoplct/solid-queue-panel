# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "puma"
gem "sqlite3"

gem "rubocop-rails-omakase", require: false
gem "tailwindcss-ruby", "~> 4.0", require: false

# json 3.0 dropped the positional options argument that Active Support 8.1 still
# passes to JSON.parse, which breaks deserializing any serialized column.
# Development only: applications pick their own json, and the incompatibility is
# Rails', not this gem's.
gem "json", "< 3"
