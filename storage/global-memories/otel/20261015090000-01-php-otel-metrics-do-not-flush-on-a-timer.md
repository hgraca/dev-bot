---
date: 2026-10-15
keywords: ["otel", "php", "metrics", "forceflush", "short-lived process"]
aliases: ["OTEL_METRIC_EXPORT_INTERVAL has no effect", "PHP OTel metrics lost in CLI", "ExportingReader"]
trigger-on: ["php-otel-metrics", "otel-metrics-flush"]
---

## The PHP OTel SDK does not export metrics on a timer — a short-lived process loses them unless force-flushed

The PHP OpenTelemetry SDK autowires an `ExportingReader`, not a periodic metric reader, so
`OTEL_METRIC_EXPORT_INTERVAL` has no effect: metric data points buffer for the process's lifetime and
are only shipped on a flush. A long-running worker can flush on its loop (this project's message-bus
flushes on the queue `Looping`/`JobFailed` events, throttled), but a **short-lived console command** —
a scheduled task — records into its in-process meter and exits before any flush, so the metric is
silently lost. `msg-bus:metrics:export` does not help: it is a _different_ process, and only computes
the pull/observable gauges it can read from external state.

Fix pattern used here: register the flush on the application's **terminating** callbacks for console
processes (`$app->terminating(...)` guarded by `runningInConsole()`), and make it a no-op when a flush
already happened in the process (a small singleton "flush state" marked by the scheduled export
path) — so a short-lived command ships its metrics at exit without making every worker flush
synchronously.

Related constraint: the OTel **metrics API has no stable synchronous gauge** —
`MeterInterface::createGauge()` is `@experimental` (it works here, but only because the consumer's SDK
implements it), and an `ObservableGauge` is pull-based, observed at export time, which for a
short-lived process is a different process that cannot read the reporting process's in-memory state.
So "last value" signals (e.g. last success time) are a poor fit for a metric; prefer a counter on
which the rule computes `increase(metric[window]) == 0`.
