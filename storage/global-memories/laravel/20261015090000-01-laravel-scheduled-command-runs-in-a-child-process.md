---
date: 2026-10-15
keywords: ["laravel", "scheduler", "scheduled-task", "subprocess", "artisan"]
aliases: ["ScheduledTaskStarting", "->command() runs out of process", "schedule:run child process"]
trigger-on: ["laravel-scheduler-context", "scheduled-task-telemetry"]
superseded_by: ["laravel/20261015092014-02-laravel-scheduled-command-string-is-not-a-label.md"]
---

## A Laravel `->command(...)` scheduled task runs in a child process, so the parent's context does not reach it

> **Superseded in part by** `laravel/20261015092014-02-laravel-scheduled-command-string-is-not-a-label.md` (2026-10-15) — the closing aside below about stripping the PHP binary does not produce a safe label; that note gives the correct parse.

`ScheduleRunCommand` dispatches `ScheduledTaskStarting` in the **parent** `schedule:run` process, but
`Illuminate\Console\Scheduling\Event::execute()` runs every `->command(...)` task as a **separate
process** (`Process::fromShellCommandline(...)->run()`, built by `CommandBuilder`). The child re-runs
its own `CommandStarting` against a fresh container with an empty/context-free state, so anything the
parent set on a request/telemetry context (a delivery-mechanism marker, correlation id, a "this is a
cron run" flag) is **absent in the child** — it falls back to `CLI`, indistinguishable from a human
running the same command. Only `->call(...)` closures (`CallbackEvent`, which overrides `execute()`
and runs in-process) and the event's `before`/`onSuccess`/`onFailure` callbacks run in the parent and
carry the parent's context.

Consequence: to tag/emit anything as a _scheduled_ run, do it from the scheduled **event's callbacks**
(the shape Sentry's own `sentryMonitor()` uses), not from inside the command body. This is the same
constraint Sentry documents ("handled by a separate process") for `runInBackground`.

Related: `Event::$command` is the full `Application::formatCommandString()` output — e.g.
`/usr/bin/php8.3 artisan report:generate --type=daily` — host-specific and parameter-bearing. Strip the
PHP binary (as `ScheduleRunCommand` does: `trim(str_replace($this->phpBinary, '', $event->command))`)
before using it as a bounded label.
