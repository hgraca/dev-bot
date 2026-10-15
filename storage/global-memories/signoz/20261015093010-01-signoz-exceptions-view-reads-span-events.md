---
date: 2026-10-15
keywords: ["signoz", "opentelemetry", "span-events", "exceptions", "clickhouse"]
aliases: ["exceptions tab empty", "exception.type returns 0 rows"]
trigger-on: ["otel-exception-recording", "signoz-exceptions-view"]
---

## SigNoz builds its Exceptions view from span events, not trace attributes

SigNoz reads exceptions from the `exception` span **event** (or an event name ending `.exception`) that `recordException` emits; log records never feed it. The events land in ClickHouse as the materialized view `signoz_traces.signoz_error_index_v2` (`exceptionType`, `exceptionMessage`, `exceptionStacktrace`, `exceptionEscaped`, `serviceName`, `groupId`) and raw in `signoz_index_v3.events`. Consequence: filtering **traces** by `exception.type EXISTS` returns 0 rows and `signoz_get_field_keys(signal="traces")` never lists `exception.type`, even when thousands of exceptions are recorded — `exception.type` is a span-event attribute, not a trace attribute. Verify exceptions with a ClickHouse query against `signoz_error_index_v2` (`SELECT serviceName, exceptionType, count() … GROUP BY …`) rather than a trace filter. `exception.escaped` is deprecated by OTel — do not set it; rows still appear in the view when it is unset/`false`.
