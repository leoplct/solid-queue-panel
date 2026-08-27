# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

### Added

- Dashboard with live counters, a throughput chart of jobs enqueued, finished
  and failed with arrival and completion rates, and health alerts.
- Processes page with supervisors, workers, thread usage gauges and jobs in
  progress.
- Queues page with per queue counters, backlog bars, latency, pause, resume and
  clear.
- Jobs browser filtered by status, queue or search, with retry, run now, discard
  and bulk actions.
- Recurring tasks with their schedule, next run and latest runs.
- Per job class metrics over a configurable period.
- Settings page with the Solid Queue configuration, the configured processes and
  the contents of `config/queue.yml` and `config/recurring.yml`.
- Sign in form with credentials that stay saved in the browser for two weeks,
  HTTP basic authentication with the same credentials, a custom authentication
  block, and read-only mode.
- `bin/rails generate solid_queue_panel:install`, which mounts the engine,
  writes the initializer and generates the first password, and
  `bin/rails solid_queue_panel:password` to roll it.
- Light and dark themes, and live refresh.
