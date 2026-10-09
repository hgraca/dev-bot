---
date: 2026-10-07
keywords: ["otel", "message-bus", "metrics", "cron"]
aliases: ["msg-bus:metrics:export", "message-bus metrics cron", "message-bus 0.17.22"]
trigger-on: ["message-bus-version-bump", "otel-metrics-export"]
---

## get-e/message-bus 0.17.22 auto-schedules a metrics-export command every minute

From `get-e/message-bus` 0.17.22 the Laravel adapter registers `php artisan msg-bus:metrics:export` on a `* * * * *` schedule by default, independent of the host app's own scheduling config; disabling the `telemetry.collectors` config stops both this cron and the in-worker flush, and the export settings were renamed under `telemetry.metrics.export`. This is the library shipping the CLI-command-plus-worker-flush workaround the PHP OpenTelemetry SDK requires (the SDK autowires an `ExportingReader`, not a periodic metric reader, so push metrics otherwise buffer for a whole worker lifetime and `OTEL_METRIC_EXPORT_INTERVAL` has no effect). A consumer upgrading to 0.17.22 should expect a new per-minute scheduled command in `php artisan schedule:list` — the audit-log `make crons` gate surfaces it — and decide whether to keep, throttle, or disable it via `telemetry.collectors`.
