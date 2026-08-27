# Solid Queue Panel

A web panel for [Solid Queue](https://github.com/rails/solid_queue), in the spirit of the Sidekiq web
UI: one place to see what your workers are doing, which queues are backing up, why a job failed, and
how the whole thing is configured.

[![CI](https://github.com/leoplct/solid-queue-panel/actions/workflows/ci.yml/badge.svg)](https://github.com/leoplct/solid-queue-panel/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

![Solid Queue Panel dashboard](docs/screenshots/dashboard.png)

Add the gem, run the installer, sign in. No migrations, no assets to precompile, no JavaScript build,
no external requests — and a sign in page so it is never accidentally public.

## Getting started

```ruby
# Gemfile
gem "solid_queue_panel"
```

```bash
bundle install
bin/rails generate solid_queue_panel:install
```

The installer mounts the panel at `/jobs`, writes `config/initializers/solid_queue_panel.rb`, and
generates the credentials you will sign in with:

```
      create  config/initializers/solid_queue_panel.rb
 credentials  stored solid_queue_panel.password
       route  mount SolidQueuePanel::Engine => "/jobs"

Solid Queue Panel is mounted at /jobs

  Username: admin
  Password: iRFMlvTckYpnJm9YuR9v8RyK

The password is stored in your encrypted credentials. Write it down: this is the
only time it is printed.
```

Start your app, open `/jobs`, and sign in with those credentials.

```bash
bin/rails generate solid_queue_panel:install --at /admin/jobs --username leonardo
```

<p align="center">
  <img src="docs/screenshots/login.png" alt="Sign in page" width="560">
</p>

### Signing in

The panel signs your browser in for **two weeks** with a signed, http-only cookie, so you type the
password once and your password manager keeps it. Sign out from the button in the navigation bar, or
change the duration:

```ruby
config.session_duration = 90.days
```

The same credentials are accepted as HTTP basic authentication, which is handy for `curl` or an
uptime check:

```bash
curl -u admin:iRFMlvTckYpnJm9YuR9v8RyK https://example.com/jobs
```

### Where the password lives

The installer stores it in your [encrypted credentials](https://guides.rubyonrails.org/security.html#custom-credentials),
under `solid_queue_panel.password`, and the generated initializer reads it from there — or from the
environment, which wins when both are set:

```ruby
config.username = ENV.fetch("SOLID_QUEUE_PANEL_USERNAME", "admin")
config.password = ENV.fetch("SOLID_QUEUE_PANEL_PASSWORD") { Rails.application.credentials.dig(:solid_queue_panel, :password) }
```

If your application has no master key, set `SOLID_QUEUE_PANEL_PASSWORD` in the environment of every
process that serves the panel instead.

### Changing the password

```bash
bin/rails solid_queue_panel:password
```

It prints a fresh random password and where to put it. Changing the password signs every browser out.

```bash
bin/rails credentials:edit   # to store the new one
```

### Other ways to protect it

Setting a username and a password turns the sign in form on. If your application already knows who
its administrators are, skip it and mount the panel behind your own authentication instead:

```ruby
# config/routes.rb
authenticate :user, ->(user) { user.admin? } do  # Devise
  mount SolidQueuePanel::Engine => "/jobs"
end
```

```ruby
# config/initializers/solid_queue_panel.rb — the block runs in the controller
config.authenticate_with { redirect_to(main_app.root_path) unless current_user&.admin? }
```

And whatever you pick, a panel that only needs to be watched can be made harmless:

```ruby
config.read_only = true   # hides and refuses retry, discard, pause, resume, clear, prune
```

> [!WARNING]
> Leaving `username` and `password` blank, with no `authenticate_with` block and no route constraint,
> leaves the panel open to anyone who can reach the URL. It can pause queues and discard jobs.

## What you get

| Page | What it shows |
| --- | --- |
| **Dashboard** | The [capacity table](#capacity-and-eta): for every queue, the threads that can work on it, what they are running right now, what is pending, when it was last added to, and when it will be empty — plus retries, scheduled and dead jobs. Along with every job being processed right now, each with a progress bar of how long it has been running against how long jobs like it take, and alerts when something is silently wrong: no worker running, dead processes, paused queues, a different Active Job adapter. |
| **Processes** | Supervisors with their workers, dispatchers and schedulers: queues polled, thread pool size and how much of it is busy, polling interval, heartbeat, and every job currently running. Dead processes can be pruned from here. |
| **Queues** | Per queue counters and a backlog bar broken down by state, plus latency — how long the oldest job has been waiting. Queues can be paused, resumed and cleared. |
| **Queue detail** | The jobs of a single queue, filtered by state: the fastest way to answer "what is stuck in this queue?". |
| **Jobs** | Every job, filtered by state, queue or search (job class, job id or Active Job id), with retry, run now, discard, bulk actions and [duplicate removal](#removing-duplicates). |
| **Job detail** | The Active Job payload, timings, attempts, concurrency key, the worker running it, and the full error with backtrace when it failed. |
| **Recurring** | Recurring tasks with their schedule, target, queue, last run and next run, plus the latest runs of each task. |
| **Metrics** | A throughput chart of jobs enqueued, finished and failed, with arrival and completion rates, and a table per job class: enqueued, finished, failed, failure rate, jobs in progress, average and total time. |
| **Resources** | [How much memory and CPU](#resource-metrics) every machine and every Solid Queue process is using, over time, what each job class costs, and concrete advice on how many processes and threads this machine can take. |
| **Settings** | The whole Solid Queue configuration with an explanation of every setting, the processes Solid Queue would start, the contents of `config/queue.yml` and `config/recurring.yml`, the database the queue lives in, and the versions in use. |

Every page refreshes itself while you watch it, in light or dark theme, and works down to a phone
screen.

### Screenshots

<table>
  <tr>
    <td width="50%"><a href="docs/screenshots/queues.png"><img src="docs/screenshots/queues.png" alt="Queues"></a><br><em>Queues, with backlog bars and latency</em></td>
    <td width="50%"><a href="docs/screenshots/processes.png"><img src="docs/screenshots/processes.png" alt="Processes"></a><br><em>Processes, threads and jobs in progress</em></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/screenshots/jobs.png"><img src="docs/screenshots/jobs.png" alt="Jobs"></a><br><em>Jobs, filtered by state, with bulk actions</em></td>
    <td width="50%"><a href="docs/screenshots/duplicates.png"><img src="docs/screenshots/duplicates.png" alt="Duplicates"></a><br><em>Counting the exact copies before discarding them</em></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/screenshots/resources.png"><img src="docs/screenshots/resources.png" alt="Resources"></a><br><em>Memory, CPU and tuning advice per machine</em></td>
    <td width="50%"><a href="docs/screenshots/settings.png"><img src="docs/screenshots/settings.png" alt="Settings"></a><br><em>Settings: the whole Solid Queue configuration</em></td>
  </tr>
  <tr>
    <td width="50%"><a href="docs/screenshots/metrics.png"><img src="docs/screenshots/metrics.png" alt="Metrics"></a><br><em>Throughput and metrics per job class</em></td>
    <td width="50%"><a href="docs/screenshots/dashboard-dark.png"><img src="docs/screenshots/dashboard-dark.png" alt="Dark theme"></a><br><em>Dark theme, following the system by default</em></td>
  </tr>
</table>

### Capacity and ETA

The table on the dashboard answers the question you actually have when a queue starts growing: is
there anyone working on it, and when will it be done?

- **Last 24h** is the shape of the day: jobs finished as a filled area, jobs arriving as a dashed
  line over it, hour by hour. A line pulling away from the area is a queue being fed faster than it
  is drained, long before the pending count makes it obvious.
- **Capacity** is the number of worker threads polling the queue, wildcards resolved the way Solid
  Queue resolves them. A worker polling several queues lends its threads to all of them, so
  capacities overlap: the number says how many jobs of that queue *could* be running right now.
- **In progress** is what those threads are doing, green until 70% of the capacity, amber up to 95%,
  red when every thread is taken.
- **Pending** is what is waiting in the queue, and **Last added** is how long ago the queue was last
  added to.
- **ETA** spreads the work waiting over the threads that can pick it up, using [what jobs like those
  usually take](#how-long-a-job-takes). When some of the jobs waiting have never been seen before the
  estimate is shown as a floor ("at least 4m"), and when none of them has, it says `unknown` rather
  than making something up.
- The remaining columns are every state Solid Queue can put a job in: **Blocked** by a concurrency
  limit, **Scheduled** for later, **Retries** for the ones that already raised and will run again,
  **Dead** for the ones that failed and will not be retried until you say so, and **Finished 24h** for
  the ones that made it, for as long as Solid Queue keeps them. Each number is a link to that list.

### How long a job takes

Estimates — the ETA of a queue, the progress bar of a running job — are only as good as what they are
based on, so the panel looks for the most specific answer it has and says which one it used:

1. **The same job with the same arguments.** `SyncJob.perform_later(10)` and
   `SyncJob.perform_later(2_000)` are the same class and rarely the same amount of work, so runs are
   remembered per set of arguments. This needs the [resource metrics](#resource-metrics), which record
   the execution time measured inside the workers.
2. **The same job class**, when those particular arguments have never been seen.
3. **Nothing.** No history, no estimate: the panel shows `unknown` and no progress bar, instead of a
   number that would be a guess.

Hovering a progress bar tells you when the job is expected to finish, how many runs the estimate is
based on, and whether those runs were measured inside the worker or inferred from the time between
enqueue and completion. A bar that fills past 100% turns red: the job is taking longer than its
history says it should.

### Removing duplicates

The queued tab has a **Remove duplicates** button. It opens a page that counts the copies first and
lists what they are copies of, so discarding them is a decision rather than a surprise — and so the
count, which walks the queue, only runs when you ask for it rather than on every page you look at.
Confirming discards every copy but the first of each group.

Exact is meant literally. Two jobs are copies only when all of this matches:

- the job class, the queue and the priority,
- the concurrency key,
- the entire Active Job payload: arguments, locale, timezone, number of attempts, everything.

The only fields ignored are the ones Active Job generates for every single job and that therefore can
never be equal: `job_id`, `enqueued_at` and `provider_job_id`.

Only jobs still waiting in their queue are considered. A job a worker has already claimed, or a
scheduled, blocked or failed one, is never touched — and neither is the first copy of each group.
Discarding goes through Solid Queue, so any concurrency lock the discarded jobs held is released.

The scan compares payloads in Ruby, so it stops at the 100,000 oldest queued jobs and tells you how
many it looked at. Run it again to work through a longer queue.

## Resource metrics

The panel can measure how much memory and CPU Solid Queue is actually using, on every machine, and
what each job class costs. It is not installed by default because it needs two tables of its own:

```bash
bin/rails generate solid_queue_panel:resource_metrics
bin/rails db:migrate
```

Restart your Solid Queue processes and the **Resources** page fills up. The migration goes to the
migrations path of the database Solid Queue uses, so a dedicated queue database is handled on its own.

What gets recorded, from inside the Solid Queue processes themselves:

- **Per process**, every 30 seconds: resident memory and CPU, plus the memory, cores and load average
  of the machine. In a container the cgroup limits are read instead of the size of the host, which is
  what you want on Kubernetes, Docker or a Heroku-style dyno.
- **Per job class, and per set of arguments**, accumulated in memory and written on the same tick: how
  many jobs ran, how long they took, how much CPU they used (measured on the thread that ran the job)
  and how much the process grew while they ran. Jobs called with a different argument every time would
  fill the table with rows nobody will ever read, so only the most frequent sets of each tick are kept
  — at most 25 per class — while the total of the class is always written.

That is one row per process per sample, and a handful of rows an hour for the job usage — no matter
how many jobs run. Samples are pruned after three days.

The page turns it into the two decisions you have to make:

> Each worker holds 233 MB, and the machine is using 64% of its 8,192 MB. There is room for about 10
> worker processes of that size.
>
> Load average is 2.26 on 4 cores, 56% per core. The machine is comfortably busy.
>
> Running 3 processes × 5 threads. A starting point to measure against: 4 × 5.

...along with the `config/queue.yml` snippet for that suggestion, and a table of the job classes that
are burning the most CPU and growing the process the most.

Memory attribution has one honest caveat: resident memory belongs to the whole process, so when a
worker runs several threads the growth attributed to one job is an indication rather than an invoice.
CPU time is per thread, and exact.

## Requirements

- Ruby 3.2 or newer
- Rails 7.2 or newer
- Solid Queue 1.0 or newer

## Installing by hand

If you would rather not run the generator:

```ruby
# config/routes.rb
mount SolidQueuePanel::Engine => "/jobs"
```

```ruby
# config/initializers/solid_queue_panel.rb
SolidQueuePanel.configure do |config|
  config.username = ENV["SOLID_QUEUE_PANEL_USERNAME"]
  config.password = ENV["SOLID_QUEUE_PANEL_PASSWORD"]
end
```

That is the whole installation. The panel reads the tables Solid Queue already has, and serves its
own CSS and JavaScript from the gem, so there is nothing to migrate and nothing to add to your asset
pipeline (it works the same with Propshaft, Sprockets or neither).

## Configuration

Everything is optional except the credentials. These are the defaults:

```ruby
SolidQueuePanel.configure do |config|
  # Sign in credentials. Both must be set for the sign in form to be enabled.
  config.username = nil
  config.password = nil

  # How long a browser stays signed in.
  config.session_duration = 2.weeks

  # Name shown in the navigation bar, next to the logo.
  config.application_name = nil

  # Rows per page in every table.
  config.page_size = 25

  # Seconds between two live refreshes. Set to 0 to disable polling entirely.
  config.polling_interval = 5

  # Hide and refuse every destructive action.
  config.read_only = false

  # Periods (in hours) offered by the dashboard and metrics time filters.
  config.time_periods = [ 1, 6, 24, 24 * 7 ]

  # Record memory and CPU from inside the Solid Queue processes. Nothing is
  # recorded until the resource metrics tables are installed, whatever this is.
  config.record_resource_metrics = true

  # Seconds between two resource samples, per process.
  config.resource_sample_interval = 30.seconds

  # How long samples and per job class usage are kept.
  config.resource_retention = 3.days

  # Controller the panel controllers inherit from. Use it to reuse the
  # authentication, layout or callbacks of your own admin section.
  config.base_controller_class = "ActionController::Base"

  # Authenticate with the host application instead of the sign in form.
  # config.authenticate_with { redirect_to(main_app.root_path) unless current_user&.admin? }
end
```

Visitors can switch between the light, dark and system themes, and pause the live refresh, from the
navigation bar. Both choices are remembered in their browser.

## Notes for large installations

The panel is built to stay cheap on databases with millions of jobs:

- Counters that could scan a large table are bounded. "Finished 24h" counts the last day only, using
  the index on `finished_at`.
- Queue counters are collected with a handful of grouped queries, whatever the number of queues.
- The throughput chart buckets timestamps in SQL (PostgreSQL, MySQL/MariaDB and SQLite), so it never
  loads a day worth of rows into memory.
- Metrics average durations over the most recent 5,000 finished jobs of the period, and say so in the
  page when the sample is capped.
- Live refresh is a single request per interval, it pauses while you are typing or selecting rows,
  and it stops when the tab is in the background. Raise `polling_interval` or set it to `0` if you
  want less traffic.
- The resource recorder writes one row per process every 30 seconds and a handful of rows an hour for
  the job usage, whatever the throughput, and prunes itself after three days.

Two things to know about the data itself, both coming from Solid Queue rather than from this gem:

- Finished jobs are only visible while they are kept. If `SolidQueue.preserve_finished_jobs` is
  disabled, the finished tab, the chart and the metrics have nothing to show, and the panel says so
  instead of pretending everything is idle.
- Solid Queue does not record when a job *started* running, so durations are measured from enqueue to
  completion and include the time spent waiting in the queue.

## Multi-database setups

Nothing to do. The panel talks to Solid Queue's own models, so it follows whatever
`SolidQueue.connects_to` (or `config.solid_queue.connects_to`) points at, including a dedicated queue
database.

## Coming from Sidekiq

| Sidekiq | Here |
| --- | --- |
| Busy | **Processes**, with the jobs in progress at the bottom |
| Queues | **Queues** |
| Retries | **Jobs → Scheduled**: Solid Queue re-schedules a job for its next attempt |
| Scheduled | **Jobs → Scheduled** |
| Dead | **Jobs → Failed**: Solid Queue keeps failed jobs until you retry or discard them |
| Metrics | **Metrics**, and **Resources** for what the workers cost |
| Cron jobs (Sidekiq Enterprise) | **Recurring** |
| — | **Settings**, which has no Sidekiq equivalent |

Solid Queue also has a state Sidekiq does not: **blocked** jobs, waiting on a concurrency limit, get
their own tab and counter.

## Development

```bash
git clone https://github.com/leoplct/solid-queue-panel.git
cd solid-queue-panel
bundle install

bin/dev            # dummy app with a seeded queue, on http://localhost:3010
bundle exec rake test
bundle exec rubocop
```

`bin/dev` rebuilds the CSS, recreates the dummy application's database, fills it with a realistic mix
of jobs, processes and recurring tasks, and starts the server.

The stylesheet is Tailwind CSS v4, built from `app/assets/stylesheets/solid_queue_panel/application.css`
into `app/assets/builds/solid_queue_panel.css`, which is committed so the gem needs no build step when
installed. After changing any view or helper class:

```bash
bundle exec rake tailwind:build   # or rake tailwind:watch while working
```

## Contributing

Bug reports and pull requests are welcome on GitHub. Please run `bundle exec rake test` and
`bundle exec rubocop` before opening one, and rebuild the CSS bundle if you touched the markup.

## Credits

- [Solid Queue](https://github.com/rails/solid_queue), by 37signals, which does all the actual work.
- The [Sidekiq](https://github.com/sidekiq/sidekiq) web UI, for setting the standard this panel aims
  at, and the [RabbitMQ management UI](https://www.rabbitmq.com/docs/management), for the idea of
  charting arrivals next to completions.
- [Heroicons](https://heroicons.com), MIT licensed, inlined into the gem.

## License

Released under the [MIT License](LICENSE.txt).
