---
date: 2026-11-12
keywords: ["sentry", "environment", "volume-spike", "shared-dsn", "retry-storm"]
aliases: ["sentry spike", "error volume", "external testing", "quota"]
trigger-on: ["sentry-volume-spike", "sentry-shared-dsn", "sentry-environment-tag"]
---

## Attribute a Sentry volume spike by environment before anything else

When one Sentry project carries several environments (common when staging reuses the production DSN via a
shared Kubernetes secret), the project total is a blend and a "production error spike" is often entirely
non-production. **Group by `environment` first** — `count()` with `fields: ["environment", "count()"]` over
24h and 30d — before reading any issue list, and do not trust the issue's `firstSeen` (it is clipped to the
retention window, so an old issue shows a recent first seen).

Signatures worth recognising:

- A flat hourly rate (e.g. exactly 1,380/h for many consecutive hours) is a **retry backoff**, not fresh
  traffic: message-bus retries every 3600s after the 5th attempt, and each attempt usually reaches Sentry
  twice (handled + unhandled). Confirm by filtering one issue's events on a single business id — the same id
  at the same minute past each hour is the 1h step.
- A **mass dispatcher** (one cron run enqueueing one async command per record) multiplies the retry
  amplifier by the record count: a permanent per-record failure becomes `records × 22 × 2` events. The
  fix is to make the failure non-retryable, not to raise the threshold.
- Count distinct failing jobs in the queue table (`failed_jobs`, `payload->>'$.displayName'`), not in Sentry
  — one failing job generates dozens of events, so the two counts differ by an order of magnitude.

Before concluding "we fixed it", check `find_dropped_events` for the same window: a zero-error stretch can
be `error_usage_exceeded` or `spike_protection` dropping data rather than a fix.
