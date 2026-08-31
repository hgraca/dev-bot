---
date: 2026-07-29
keywords: ["otel", "php", "span", "defensive", "nullable"]
---

## Wrap OTel span creation in try/catch and use ?-> for cleanup

When integrating OpenTelemetry into non-critical code paths (CLI consumers, background jobs), wrap all span operations in try/catch so a telemetry failure (missing extension, broken config, TracerProvider exception) never blocks business logic. Return `[null, null]` from the helper on failure and use PHP's nullsafe operator in `finally`:

```php
[$span, $scope] = $this->startSpan($message, $logger);
try {
    // business logic
} finally {
    $span?->end();
    $scope?->detach();
}
```

Log failures at critical level with enough context (topic, partition, offset) to diagnose telemetry issues without losing the actual message processing. Cache the tracer in a private property (`?TracerInterface`) so initialization fails once, not per-message.
