---
date: 2026-10-15
keywords: ["sentry", "check-in", "cron-monitor", "configureScope", "getOptions"]
aliases: ["captureCheckIn extra data", "monitor check-in custom fields", "Sentry scope vs withScope"]
trigger-on: ["sentry-check-in", "sentry-cron-monitor", "sentry-scope"]
---

## A Sentry cron check-in cannot carry custom data, and `configureScope` is not the transient scope

`Sentry\CheckIn` exposes exactly `id`, `monitorSlug`, `status`, `release`, `environment`, `duration`
and `monitorConfig` — there is no contexts/extra field and no wire-level extension point. So arbitrary
data (which command produced a run, its arguments) **cannot** be attached to a check-in; the check-in
UI in Sentry will never show it. The only channel is the Sentry **scope**: attach a tag/context with
`Sentry\configureScope(fn (Scope $s) => $s->setTag(...))`, and it rides on the events captured in that
scope (searchable, visible on issues) — not on the check-in.

Two traps found while doing this:

1. **`configureScope` mutates the process-wide scope and persists**; the transient variant is
   `Sentry\withScope(callable)`, which isolates the scope to the callback and removes it after (that
   is what this project's `SentryCollector::collectContext()` uses). `configureScope` sets a tag that
   outlives the run — in a long-lived worker or a multi-task `schedule:run`, later, unrelated events
   get misattributed to whichever command last set it.
2. **Never ship a command's arguments/options to Sentry.** Symfony's `Input::getOptions()` returns
   `array_merge($definition->getOptionDefaults(), $this->options)` — i.e. _every_ option the command
   defines, not just the ones passed — so a command invoked with `--token=…`, `--password=…` or
   `--api-key=…` would publish those values to a third party, attached to every event captured while
   it runs. Send at most the command **name** (bounded, non-sensitive), never the values.

Also: `Sentry\captureCheckIn($slug, $status, $duration, ?MonitorConfig $monitorConfig, ?string $checkInId)`
returns the id for an `in_progress` check-in; the terminal `ok`/`error` call must pass that id back
(5th arg, after `MonitorConfig`) to close the same run, otherwise the in-progress one dangles and a
second check-in is created.
