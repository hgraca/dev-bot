---
date: 2026-11-17
keywords: ["php", "opentelemetry", "sem-conv", "composer", "laravel"]
aliases: ["MESSAGING_SYSTEM undefined constant", "semconv 1.45", "opentelemetry-auto-laravel queue warning"]
trigger-on: ["opentelemetry-php-install", "composer-dependency-pin"]
---

## Pin the OTel SDK and sem-conv together — sem-conv 1.45 removed the constant the Laravel queue hook reads

`open-telemetry/sem-conv` **1.45.0** removed `Incubating/Attributes/MessagingIncubatingAttributes::MESSAGING_SYSTEM` (1.44.0 still has it at line 394; 1.45.0 ships 33 constants and not that one). `open-telemetry/opentelemetry-auto-laravel` — including the latest 1.10.0 — still reads it in `Hooks/Illuminate/Queue/AttributesBuilder.php`, and only requires `sem-conv ^1.38`, so composer resolves the broken pair without complaint. Every Redis queue push then logs `PHP Warning: Illuminate\Queue\RedisQueue::pushRaw(): OpenTelemetry: pre hook threw exception ... Undefined constant ...MessagingIncubatingAttributes::MESSAGING_SYSTEM` — on a busy worker that is tens of thousands of warning lines per hour, which buries real errors and inflates log ingest.

Pinning `sem-conv` alone does not work in either form: `open-telemetry/sdk` **1.16.x requires `sem-conv ^1.45.0`** (1.15.0 requires `^1.38`), so a lock with sdk 1.16 + sem-conv 1.44 is unsatisfiable; and listing `sem-conv` in `require` fails `composer-dependency-analyser` with `UNUSED_DEPENDENCY`, because no code imports it. The working shape is a requirement on the SDK plus a conflict on sem-conv:

```json
"require":  { "open-telemetry/sdk": ">=1.14 <1.16" },
"conflict": { "open-telemetry/sem-conv": ">=1.45" }
```

A `conflict` states exactly the incompatibility without claiming a dependency, and it fails resolution loudly for anyone who later bumps the SDK. In a shared library that every service requires, the same `conflict` propagates the guard to all consumers. Remove both once the instrumentation stops reading the removed constant.
