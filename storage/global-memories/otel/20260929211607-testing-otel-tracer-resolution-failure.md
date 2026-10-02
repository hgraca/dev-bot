---
date: 2026-09-29
keywords: ["otel", "phpunit", "tracer-provider", "testing"]
trigger-on: ["otel-tracer-failure-test", "globals-tracer-provider"]
---

## Testing an OTel tracer-resolution failure: attach a throwing provider to the current Context

`Globals::tracerProvider()` resolves from `Context::getCurrent()` first (`ContextKeys::tracerProvider()`) and only then falls back to the process-global provider, so a test can force a resolution failure without touching statics: `Context::storage()->attach(Context::getCurrent()->with(ContextKeys::tracerProvider(), new ThrowingTracerProvider()))`, with `$scope->detach()` in `finally`. That makes the failure branch of a defensive helper — the `catch (Throwable)` around `Globals::tracerProvider()->getTracer(...)` — directly testable: assert the helper returns its neutral value *and* that it logged, using a tiny recording PSR-3 logger fake (`psr/log` 3.x ships no `TestLogger`). Prefer that Context-scoped approach over `Globals::reset()` for isolation: `Globals::$initializers` is process-global and append-only, and the active Context still carries its own provider.
