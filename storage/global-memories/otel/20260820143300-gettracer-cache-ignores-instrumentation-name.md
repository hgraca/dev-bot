---
date: 2026-08-20
keywords: ["otel", "tracer", "cache", "instrumentation"]
trigger-on: ["otel-gettracer-cache-by-name"]
---

## Cache getTracer() results per instrumentation name, not in one slot

Caching the first `Globals::tracerProvider()->getTracer($name)` result in a single property silently serves that tracer for every later name, attributing spans to the wrong instrumentation scope. The noop provider (no SDK installed) returns the same instance for every name, so the bug is invisible in dev/CI — only a real SDK or a recording provider reveals it. Store `array<string, object>` keyed by `$name` and consult the provider once per unique name.
