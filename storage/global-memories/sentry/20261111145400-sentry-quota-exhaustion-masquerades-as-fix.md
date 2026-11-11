---
date: 2026-11-11
keywords: ["sentry", "error_usage_exceeded", "spike_protection", "dropped-events"]
trigger-on: ["sentry-query", "sentry-error-volume"]
---

## Sentry drops events when the org quota is spent — flatlines are not fixes

A steady error stream that suddenly reads zero, or a chart that plateaus below its trend, may be
**dropped** events rather than a resolved problem. When a project or org exceeds its error quota Sentry
stops accepting and records the loss, so accepted-only views (issue counts, `search_errors` aggregates)
understate what the application actually emitted.

Two reasons to watch for, both seen on 2026-11-11 in the `core` project:

- `error_usage_exceeded` — the org error quota is spent; events are discarded until it resets. 6,702
  events were dropped this way in a single day.
- `spike_protection` — Sentry's own rate limiting, which can drop thousands from one noisy bucket.

The tooling surfaces this as a note on the query result plus `find_dropped_events` for the breakdown by
outcome and reason. Read it before concluding anything from a drop to zero: in the case above, hours
02:00–07:00 showed zero errors purely because of drops, while the underlying loop kept running and
resumed visible reporting afterwards.

Cross-check with a second signal when the diagnosis matters — node-level log collection (SigNoz/OTel)
is independent of the Sentry DSN and keeps seeing the errors even when Sentry is disabled or dropping.
