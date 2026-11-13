---
date: 2026-11-13
keywords: ["message-bus", "LimitedFailuresMessage", "maxExceptions", "retries"]
aliases: ["non-retryable command", "retry cap", "queue retry storm"]
trigger-on: ["message-bus-limited-failures"]
---

## Cap async-command retries with `LimitedFailuresMessage`, not a local middleware

`GetE\MessageBus\Port\MessageBus\LimitedFailuresMessage::maxFailures()` is copied by `AsyncCommandEnvelope` onto Laravel's `maxExceptions`, and `Worker::markJobAsFailedIfWillExceedMaxExceptions()` fails the job once `maxExceptions <= cache->increment('job-exceptions:<uuid>')`. The counter's cache entry is written with a 24h TTL, so the default `maxExceptions = 22` (with `tries = 1000`) means a permanently failing job retries ~22 times a day, forever — a stuck command plus a daily re-dispatch produces a flat hourly Sentry stream rather than a spike. Values 0 and 1 behave identically (the first exception increments to 1, so `0 <= 1` and `1 <= 1` both fail): return 1 for "fail on the first attempt". Prefer this interface over a project-local exception marker + middleware, which swallows the exception when it marks the envelope permanently failed and therefore emits no Sentry event — use the middleware only when the failure must not alert at all.
