---
date: 2026-10-22
keywords: ["signoz", "cron-missed", "absentFor", "in_total"]
aliases: ["daily cron alert", "missed run rule", "batch job alerting"]
---

## Alerting on a daily cron needs a window longer than its period, not just `absentFor`

Every existing `cron-missed-*` rule pattern assumes a sub-hour cadence: `evalWindow: 5m`, `frequency: 1m`, `alertOnAbsent: true`, `absentFor: 10` (minutes). Copying that shape for a **daily** `0 0 * * *` job produces an alert that fires continuously, because "no data for 10 minutes" is the normal state for 24 hours a day.

Two constraints decide the design. `absentFor` is in **minutes** and must exceed the run period (25h → `absentFor: 1500`), and the rolling `evalWindow` must be longer than the period too, otherwise yesterday's run falls outside the window even when the job is healthy. The explicit condition is easier to reason about than absent-detection: `count()` over a 25h window with `matchType: in_total` and `target: 1`, `op: below` fires when zero runs happened, and gives an hour of slack over a midnight schedule. Pair it with the matching `absentFor` so both mechanisms agree.

Two traps: the existing `cron-missed-*` family in `observability/` watches **in-app scheduler spans** (`DriverScheduleScheduler.schedule` from a long-running deployment), so it does not cover k8s **CronJob** workloads at all — there is no template to copy, the span name differs and must be discovered first. And a rule keyed on a span that has never existed fires forever: confirm the run span is actually being emitted (in a lower environment) before applying, or the first 25h is a guaranteed false critical.
