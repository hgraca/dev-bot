---
date: 2026-07-29
keywords: ["otel", "php", "laravel", "monolog", "span-context"]
---

## OtelJsonFormatter silently skips trace context when span is invalid

`GetE\PhpOverlay\Otel\OtelJsonFormatter` only injects `trace_id` and `span_id` into Monolog JSON records when the active OTel span passes three checks: `class_exists(Context::class)`, `$span->isRecording()`, and `$spanContext->isValid()`. If any check fails, trace context is omitted silently — the log record still outputs but without correlation IDs.

The most common silent-failure pattern is `Span::getInvalid()->storeInContext(Context::getCurrent())`, used to clear stale context between queue/Kafka messages. Since the invalid span returns false for both `isRecording()` and `isValid()`, all logs during that scope lack trace context.

Fix: after clearing stale context, create a proper root span via `tracerProvider()->getTracer(...)->spanBuilder(...)->startSpan()` and `$span->activate()` so the formatter detects an active, recording span.
