---
date: 2026-06-17
keywords: ["otel", "opentelemetry", "laravel", "auto-instrumentation"]
---

## OTEL PHP auto-instrumentation requires OTEL_PHP_AUTOLOAD_ENABLED=true

The `open-telemetry/opentelemetry-auto-laravel` package (v1.7.0) auto-creates spans for HTTP requests, DB queries, queue jobs, and records exceptions — but only when `OTEL_PHP_AUTOLOAD_ENABLED=true` is set as an environment variable. Without it, the package installs but no instrumentation activates. The PECL extension `pecl install opentelemetry` (the engine) and `docker-php-ext-enable opentelemetry` must also be present. Required env vars: `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT`. No PHP code changes needed — install extension, composer packages, set env vars, restart.
