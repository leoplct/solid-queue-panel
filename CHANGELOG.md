# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

### Added

- Capacity table on the dashboard: threads polling each queue, what they are
  running, what is pending, when the queue was last added to, an ETA for the
  backlog, and the retried, scheduled and dead jobs of each queue. Underneath,
  a sparkline of the last 24 hours of each queue, and underneath,
  every job being processed at this moment, with a progress bar of how long it
  has been running against how long jobs like it take, and the expected finish
  time on hover.
- Estimates based on the same job with the same arguments, falling back to the
  job class and then to nothing at all: no history means no estimate, rather
  than a guess.
- Resources page: memory and CPU of every machine and every Solid Queue process
  over time, the resource cost of each job class, and advice on how many
  processes and threads the machine can take. Opt in with
  `bin/rails generate solid_queue_panel:resource_metrics`.
- "Remove duplicates" on the queued tab, which discards jobs that are an exact
  copy of an earlier one.
- Throughput chart of jobs enqueued, finished and failed, with arrival and
  completion rates, on the metrics page.
- Health alerts for the things that are silently wrong: no worker running, dead
  processes, paused queues, a different Active Job adapter.
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
