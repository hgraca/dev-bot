---
date: 2026-08-20
keywords: ["otel", "phpstan", "opentelemetry", "span-builder", "strict-types"]
trigger-on: ["otel-phpstan-strict-stubs"]
---

## open-telemetry/api PHPStan stubs are stricter than their PHP signatures

`open-telemetry/api` ships phpdoc annotations PHPStan enforces beyond the raw PHP type hints: `TracerInterface::spanBuilder()` is `@param non-empty-string`, and `SpanBuilderInterface::setSpanKind()` is `@psalm-param SpanKind::KIND_*` (i.e. `0|1|2|3|4`). Calling them with a generic `string`/`int` parameter at PHPStan level max produces `argument.type` errors that need `// @phpstan-ignore argument.type` — even though the runtime signatures accept `string`/`int`. This is a real suppression, not a dead one; do not remove it. Verify against the installed package's stubs (vendor/open-telemetry/api/Trace/*.php) before declaring such annotations dead.
