---
date: 2026-10-06
keywords: ["otel", "metrics", "php", "export", "worker"]
trigger-on: ["otel-metrics-php", "php-otel-metrics-export"]
---

## The PHP OTel SDK has no periodic metric export — drive it from a CLI command plus a worker flush

In `open-telemetry/sdk` 1.14 the autoloaded `MeterProviderFactory` wires an `ExportingReader`, not a `PeriodicExportingMetricReader`; `MetricReader/` contains only `ExportingReader.php` and no periodic reader exists in the SDK (upstream issue #1884). `ExportingReader` exports only on `collect()` / `forceFlush()` / `shutdown()`, and the SDK registers a shutdown flush — so an FPM request flushes at request end, but a long-running `queue:work` worker flushes only when it dies, buffering metrics for the worker's whole life. `OTEL_METRIC_EXPORT_INTERVAL` is documented but has no effect. Consequence: emit pull metrics (gauges read from Redis/DB/broker) from a short-lived CLI command that registers the instruments, `forceFlush()`es and exits, and flush push metrics from the worker on a throttle (Laravel's `Looping` fires every iteration including idle; `JobFailed` covers failures). `forceFlush()` is synchronous and returns `false` on timeout/export failure without throwing — check the boolean. Lower `OTEL_EXPORTER_OTLP_TIMEOUT` so an in-worker flush cannot stall the worker. `opentelemetry-auto-laravel` carries no metric wiring and no `forceFlush` at all.
