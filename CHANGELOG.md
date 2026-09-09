# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Job payloads are filtered by key wherever they are shown, reusing the
  application's `config.filter_parameters` by default, with
  `config.filter_parameters` to override it and `config.hide_job_arguments` to
  show none of them at all.
- An audit trail: every action that changes something is written to
  `config.audit_logger` and published as an `ActiveSupport::Notifications`
  event, naming the actor `config.audit_actor` returns, or how the request was
  authenticated when nothing can name a person.
- A security policy, Dependabot, and a CI job checking dependencies against the
  Ruby advisory database.

### Fixed

- Every page works again when the optional resource metrics tables were never
  installed. Passing a `JobUsage` scope as an argument loaded the model's schema
  before the guard inside the method ran, so applications without those tables
  got `PG::UndefinedTable` on the dashboard and on the settings report.

## [0.1.0]

### Added

- Capacity table on the dashboard: threads polling each queue, what they are
  running, what is pending, when the queue was last added to, an ETA for the
  backlog, and a column for every state Solid Queue can put a job in: pending,
  in progress, blocked, scheduled, retrying, dead and finished. Underneath,
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
- "Retry all", "Run all now" and "Release all", which put every job of the
  failed, scheduled and blocked lists back to work, filters included.
- "Duplicates" on the queued tab, which counts the exact copies of an
  earlier job on a page of its own, shows what they are copies of, and discards
  them once confirmed.
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
  the contents of `config/queue.yml` and `config/recurring.yml`, and a Copy
  button that puts a plain text report of the whole installation — settings,
  processes, queues, machines, config files, never credentials — on the
  clipboard, ready to paste into an LLM or an issue.
- Sign in form with credentials that stay saved in the browser for two weeks,
  HTTP basic authentication with the same credentials, a custom authentication
  block, and read-only mode.
- `bin/rails generate solid_queue_panel:install`, which mounts the engine,
  writes the initializer and generates the first password, and
  `bin/rails solid_queue_panel:password` to roll it.
- Light and dark themes, and live refresh.
