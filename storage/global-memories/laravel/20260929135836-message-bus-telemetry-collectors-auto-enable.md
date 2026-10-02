---
date: 2026-09-29
keywords: ["laravel", "message-bus", "telemetry", "opentelemetry", "sentry"]
trigger-on: ["message-bus-telemetry-config", "message-bus-version-bump"]
---

## get-e/message-bus >= 0.17.18.0 silently auto-enables Sentry + OTel telemetry collectors

`LoggerServiceProvider` resolves telemetry collectors from `message_bus.telemetry.collectors`: when the key is ABSENT it auto-detects — `SentryCollector` if `sentry/sentry-laravel` (`Hub`) is installed, and `OtelCollector` if `open-telemetry/api` (`Globals`) is installed. Both are common in GET-E Laravel apps, so upgrading to 0.17.18.0 turns bus telemetry on *everywhere* with no config change: bus middleware get wrapped in `TracingMiddlewareDecorator` (a span per dispatch) and bus events are recorded as OTel span events. To disable, set `collectors` to an explicit empty list (`[]` or `null`) — an absent key is NOT "off". Drive that per environment when the app should only trace in staging/production. This is a patch tag (0.17.17.0 → 0.17.18.0), so the behaviour change is easy to miss in a routine `composer require`.
