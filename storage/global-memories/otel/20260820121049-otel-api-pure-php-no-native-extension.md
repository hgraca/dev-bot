---
date: 2026-08-20
keywords: ["otel", "opentelemetry", "ext-opentelemetry", "composer", "instrumentation"]
trigger-on: ["otel-api-vs-native-extension"]
---

## open-telemetry/api is pure PHP — only auto-instrumentation packages force ext-opentelemetry

`open-telemetry/api` (Globals, tracers, span builders, W3C TraceContext) is pure PHP and runs without the native `ext-opentelemetry` PECL extension. Only auto-instrumentation packages like `open-telemetry/opentelemetry-auto-laravel` require `ext-opentelemetry: "*"` (they pull sem-conv plus `_register.php` auto-instrumentation hooks). When instrumenting manually via the API only, do not add `ext-opentelemetry` or auto-instrumentation packages to require-dev — they force every dev/CI environment to install a native extension (plus protobuf/PECL build deps in Dockerfiles) for no code benefit. A defensive-availability check like `class_exists(Globals::class)` already handles the library being absent.
