---
date: 2026-10-07
keywords: ["laravel", "message-bus", "telemetry", "otel", "metrics"]
aliases: ["get-e message-bus upgrade", "msg-bus metrics export command", "message-bus telemetry cron"]
trigger-on: ["message-bus-version-upgrade", "laravel-message-bus-telemetry"]
---

## get-e/message-bus 0.17.20–0.17.22: OTel metrics, a default export cron, and two interface changes

Releases 0.17.20–0.17.22 are telemetry/metrics-heavy. 0.17.20 adds OTel metrics for queues, message dispatch/handling, latency and queries, and makes `GetE\MessageBus\Port\Telemetry\TelemetryCollector` gain metric methods plus `getMeter()` (BREAKING only for custom collector implementations — the package's Null/Sentry collectors and `Composite` are updated; a project with no custom impl needs no change). 0.17.21 makes the second-level query cache serialize its own results with no allowlist, so any `SecondLevelCacheableQuery` result must be a scalar, `null`, or a `GetE\MessageBus\Port\QueryBus\CacheSerializable`. 0.17.22 registers a `msg-bus:metrics:export` schedule every minute by default (`Config::boolean('message_bus.telemetry.metrics.export.cron.enabled', true)`) plus a 15s worker metric flush (`telemetry.metrics.export.worker.interval`, default 15); both are gated on `MetricsExporters::active()` being non-empty, so with `telemetry.collectors = []` (typical dev/test) nothing is scheduled, while in staging/production where collectors auto-detect OTel this silently starts a per-minute cron and a worker flush — a deploy-affecting behaviour change worth flagging on a routine `composer require`. Note the app config and package defaults are merged **recursively** for associative arrays by `MessageBusServiceProvider::mergeConfigs()`, so an app-level override such as `telemetry.collectors = []` does NOT wipe the package's sibling defaults under `telemetry` (e.g. `telemetry.metrics.export.*` survive).
