---
date: 2026-08-07
keywords: ["otel", "opentelemetry", "defensive", "class_exists"]
---

## Defensive OTel service without type hints in signatures

When building an OpenTelemetry integration for a library (not an application), the service must load safely even when `open-telemetry/api` is not installed. Key patterns:

1. **Guard with `class_exists()`**: Check `class_exists(\OpenTelemetry\API\Globals::class)` once, cache result. The `::class` syntax on a fully-qualified name does not trigger autoloading.

2. **No OTel type hints in method signatures**: Use `mixed` or untyped parameters/properties. PHP will attempt to resolve return types and parameter types when the class is loaded — if the OTel class doesn't exist, the file won't parse. Use `@var` docblocks for PHPStan.

3. **All OTel calls in try/catch**: Every `Globals::tracerProvider()`, `spanBuilder()`, `startSpan()`, `end()` call is wrapped. Failures log critical and return null — never throw.

4. **Default values as primitives**: Use `int $spanKind = 0` (not `SpanKind::KIND_INTERNAL`) since the constant won't resolve without the class.

5. **Fully-qualified class names**: Use `\OpenTelemetry\API\Globals::tracerProvider()` inline instead of `use` imports, keeping the file parseable without OTel.

This pattern was copied from `OtelKafkaSpan` trait in the core project (`.ai/transfers`).
