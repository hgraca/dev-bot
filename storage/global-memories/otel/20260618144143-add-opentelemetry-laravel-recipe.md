---
date: 2026-06-18
keywords: ["otel", "laravel", "php", "opentelemetry", "tracing"]
trigger-on: ["opentelemetry-integration", "otel-laravel-setup", "php-tracing", "distributed-tracing"]
---

## Add OpenTelemetry distributed tracing to a PHP/Laravel project

To instrument a Laravel project with OpenTelemetry: (1) Add Composer packages `open-telemetry/exporter-otlp`, `open-telemetry/opentelemetry-auto-laravel`, `open-telemetry/sdk`, `php-http/guzzle7-adapter`, and `tbachert/spi` (add `tbachert/spi` to `config.allow-plugins`); (2) Install the `opentelemetry` PECL extension via `pecl install opentelemetry-1.2.1` and enable with `docker-php-ext-enable opentelemetry`; (3) Add OTEL_* env vars (`OTEL_PHP_AUTOLOAD_ENABLED`, `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT`) to all `.env*` files, varying `OTEL_PHP_AUTOLOAD_ENABLED` by environment (false for local/dev/phpunit, true for staging/production); (4) Forward OTEL env vars to PHP-FPM via `env[OTEL_*] = $OTEL_*` directives in `www.conf` (PHP-FPM does not inherit shell env vars); (5) Pass OTEL_* in the docker-compose service definition with defaults. Verify with `php -m | grep opentelemetry` and confirm traces appear in the tracing backend. The `opentelemetry-auto-laravel` package provides zero-config auto-instrumentation for HTTP requests, database queries, and cache operations.
