---
date: 2026-08-07
keywords: ["otel", "opentelemetry", "setparent", "context", "nested-spans"]
trigger-on: ["otel-setparent", "traceparent-propagation", "nested-spans"]
---

## Use Context::storage()->attach() not per-span setParent() for traceparent propagation

When propagating a W3C traceparent from HTTP headers, calling `setParent()` on every `spanBuilder()` forces ALL spans to be direct children of the remote root — destroying natural parent-child nesting of middleware spans (flattens the tree into siblings). Instead, extract the context once with `TraceContextPropagator::extract()` and attach it via `\OpenTelemetry\Context\Context::storage()->attach()`. Spans created after this will inherit the remote context as their ultimate ancestor, but intermediate spans activated via `$span->activate()` will still nest properly as children of the previous active span.
