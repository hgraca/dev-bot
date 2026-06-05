---
date: 2026-07-29
keywords: ["kafka", "otel", "php", "consumer", "span"]
---

## Kafka consumers need explicit OTel span creation per message

Laravel Artisan commands use `$this->info()` which writes to stdout, bypassing Monolog and `OtelJsonFormatter` entirely. Even if switched to `LoggerInterface` (which routes through Monolog stderr), the common pattern of `Span::getInvalid()` to clear stale context prevents trace context injection.

Fix: inject `LoggerInterface` for structured logging, then replace `Span::getInvalid()` with a proper `KIND_CONSUMER` span using `Globals::tracerProvider()->getTracer('kafka-consumer')->spanBuilder($topic)->startSpan()`. Create the span per-message with messaging attributes (system, destination, partition, offset). Activate via `$span->activate()`, end via `$span->end()` in finally. Optionally extract W3C traceparent from `$message->headers` and set as parent via `TraceContextPropagator::getInstance()->extract($headers)` + `$spanBuilder->setParent($context)`.
