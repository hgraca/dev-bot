---
date: 2026-08-20
keywords: ["laravel", "logger", "singleton", "binding", "null-logger"]
trigger-on: ["laravel-null-logger-default-binding"]
---

## A NullLogger default on a failure-tolerant port class hides failures in production

Port classes that promise to log absorbed failures (e.g. a composite telemetry collector that isolates throwing collectors) often default a `LoggerInterface` parameter to `new NullLogger()` for test convenience. If the production DI binding forgets to inject a real logger, the promised observability silently disappears. Always pass `$app->make(LoggerInterface::class)` in the binding — and note that resolving the interface inside a singleton closure returns the already-extended/decorated logger chain (e.g. context-injecting decorators), which is what you want for failure logs. Verify with a provider test asserting the resolved logger is not the NullLogger.
