---
date: 2026-10-07
keywords: ["laravel", "opentelemetry", "otel-metrics", "schedule-run", "php-fpm"]
aliases: ["pull gauges", "observable gauge", "msg-bus metrics"]
trigger-on: ["otel-metrics-export", "laravel-scheduler", "php-fpm-metrics"]
---

## Pull OTel gauges in a PHP-FPM Laravel app need a scheduled flush, not the SDK timer

The OTel PHP SDK's periodic metric reader needs a long-lived process; PHP-FPM requests and short-lived `php artisan` invocations exit before it fires, so any _observable_ (pull) gauge — e.g. the GET-E message-bus `message_bus.queue.depth` / `.rate_limiters` / `.circuit_breakers` / `.command_locks`, registered by its `OtelMetricsRegistrar`s — is never exported by the SDK alone. `get-e/message-bus` therefore ships `msg-bus:metrics:export`, a CLI command that registers the registrars and `forceFlush()`es; from 0.17.22.0 it registers that command on Laravel's `Schedule` every minute (gated by `telemetry.metrics.export.cron.enabled` and by `MetricsExporters::active()`), and it also flushes from long-running queue workers on the `Looping`/`JobFailed` events. Consequence: push-style counters recorded while handling messages (`messaging.client.sent.messages`, `message_bus.message.dispatched`) do reach SigNoz from the workers, but the pull gauges do not until the host actually runs `php artisan schedule:run` — so a Laravel service needs a scheduler CronJob, and each new service in a `deploy-*` GitOps repo must add one (see the existing `laravel` / `hotels-api` cronjobs as the pattern).
