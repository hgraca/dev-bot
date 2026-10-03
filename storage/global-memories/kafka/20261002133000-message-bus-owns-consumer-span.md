---
date: 2026-10-02
keywords: ["kafka", "message-bus", "consumer-span", "telemetry-collector", "setparent-false"]
aliases: ["OtelKafkaSpan anti-pattern", "bus-owned consumer span", "owning the consumer span"]
see: ["kafka/20260729094906-kafka-consumers-need-explicit-otel-span.md"]
supersedes: ["kafka/20260729094906-kafka-consumers-need-explicit-otel-span.md"]
trigger-on: ["kafka-consumer-span", "message-bus-consumer-span", "otel-kafka-span"]
---

## message-bus >= 0.17.19.0 owns the consumer span for bus-consumed messages

From `get-e/message-bus` 0.17.19.0 the bus opens the per-message span itself: `MessageEnvelopeHandlerAbstract::handle()` calls `TelemetryCollector::startSpan()` (CONSUMER kind when the envelope came off a broker) and `endSpan()`, parenting it to the transport W3C trace context (`ConsumedJobHeaders` / `TracingInformationCarryingMessageEnvelopeTrait`) and tagging `messaging.system` / `messaging.destination.name` / `messaging.operation`. An application that consumes through the bus must NOT hand-roll its own per-message span — the release docs name an `OtelKafkaSpan` trait as the anti-pattern because it duplicates the span and re-introduces the parent-link bug it fixes. But the bus only covers messages it consumes: an app that polls raw RdKafka directly and dispatches onto a queue (not through the bus's Kafka queue) still needs its own receive span, and should create it through the bus port — `TelemetryCollector::startSpan($topic, $message->headers, SpanKind::CONSUMER)` then `endSpan($span, $scope, $owner)` in a `finally`, with attributes added via `addTag()`. That port already extracts the parent from `traceparent` and, for a CONSUMER span with no traceparent, starts an isolated root (`setParent(false)`) — exactly what per-message isolation needs. `setRootContextFromHeaders()` is the wrong tool here: it attaches an extracted context but does not detach the ambient long-lived CLI command span.
