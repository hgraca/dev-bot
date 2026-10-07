---
date: 2026-10-07
keywords: ["otel", "globals", "memoization", "boot"]
aliases: ["opentelemetry global provider noop", "globals memoizes"]
trigger-on: ["otel-globals-lazy-provider"]
---

## Globals::meterProvider()/tracerProvider() memoise on first call — never touch them while providers boot

`OpenTelemetry\API\Globals::globals()` stores the resolved globals in a static on first access (`if (self::$globals !== null) return self::$globals;`), and `meterProvider()`/`tracerProvider()` read from it. If a service provider resolves an OTel provider during `boot()` but the host registers its SDK initializer later, the process locks in the no-op provider and ALL telemetry (traces and metrics) silently disappears with no error. Constructing any class that type-hints `MeterProviderInterface`/`TracerProviderInterface` eagerly at boot triggers this. Fix: keep such construction lazy — inject a `Closure(): MeterProviderInterface` (or a small factory) and invoke it at use time, so the global is resolved after the host SDK is registered. On the `opentelemetry-auto-laravel` path the SPI components register at Composer-autoload time (before providers boot), so it is safe there, but a manual SDK bootstrap is not guaranteed to run first.
