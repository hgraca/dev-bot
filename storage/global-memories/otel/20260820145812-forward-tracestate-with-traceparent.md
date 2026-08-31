---
date: 2026-08-20
keywords: ["otel", "tracestate", "traceparent", "propagation", "w3c"]
trigger-on: ["otel-tracestate-forwarding"]
---

## Forward tracestate together with traceparent for W3C TraceContext

The W3C propagator's `extract()` reads BOTH `traceparent` and `tracestate` from the carrier — tracestate carries vendor-specific routing/sampling state that must survive propagation. Middleware that forwards only the `traceparent` header silently drops it, breaking vendor context (e.g. sampling decisions) in downstream spans. When building a carrier from request headers, include `tracestate` whenever it is a non-empty string. The propagator handles both keys; the caller just has to pass them.
