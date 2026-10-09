---
date: 2026-10-07
keywords: ["laravel", "message-bus", "otel", "queue-depth", "otel-configmap"]
aliases: ["queue depth panel empty", "pull gauge not exported", "metrics export command"]
trigger-on: ["message-bus-otel-metrics", "laravel-schedule-cronjob-otel"]
---

## get-e/message-bus pull gauges are exported only by the schedule, so that workload needs the OTel env

For `get-e/message-bus` ≥ 0.17.20 the OTLP metrics leave the app by two paths: worker replicas flush the **push counters** (`message_bus.message.dispatched/failed/…`) on a throttled loop, while the **pull gauges** — `message_bus.queue.depth` and the circuit-breaker / rate-limiter / command-lock gauges — are registered and flushed *only* by the `msg-bus:metrics:export` command (`OtelMetricsExporter::exportFromSchedule()` runs each tagged `OtelMetricsRegistrar::register()` then `forceFlush()`s the meter provider). The library schedules that command every minute itself (`telemetry.metrics.export.cron.enabled`, default true, gated on an active collector), so in a Laravel app it runs inside whatever workload executes `schedule:run` — normally a dedicated CronJob. Consequence: if that scheduler workload lacks the OTel SDK configuration (`OTEL_PHP_AUTOLOAD_ENABLED=true` plus an OTLP endpoint; in GET-E k8s, the per-app `otel-env-<app>` configMap), `Globals::meterProvider()` is a no-op, the export command still logs `… DONE`, and the pull gauges are silently never ingested while the worker-flushed counters keep arriving. The symptom is a dashboard panel built on a pull gauge showing nothing even though other bus metrics have data. Fix: give the scheduler workload — a **CronJob**, which the usual "inject the OTEL configMap into Deployments/StatefulSets" kustomize patches miss — the same OTel env the workers get.
