---
date: 2026-08-20
keywords: ["otel", "test", "tracer", "provider", "context"]
trigger-on: ["otel-fake-tracer-provider-test"]
---

## Inject a fake OTel TracerProvider via the current context in tests

`Globals::tracerProvider()` prefers the provider stored in the CURRENT context over the global noop: `Context::getCurrent()->with(OpenTelemetry\API\Instrumentation\ContextKeys::tracerProvider(), $fakeProvider)` attached via `Context::storage()->attach()` (detach in finally). This lets tests assert per-name provider call counts even though the noop provider returns the same NoopTracer instance for every name — assert provider call counts, not instance identity. `ContextKeys` is `@internal` but usable from tests.
