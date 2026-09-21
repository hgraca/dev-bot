---
date: 2026-09-21
keywords: ["otel", "php-fpm", "clear_env", "www.conf", "opentelemetry"]
trigger-on: ["php-fpm-env-config", "opentelemetry-php-fpm"]
---

## PHP-FPM `env[]` passthrough must include the OTEL disable switches, not just the exporter vars

PHP-FPM's default `clear_env = yes` wipes the process environment before workers spawn, so every OTEL variable a worker needs must be declared explicitly as an `env[NAME] = $NAME` line in `www.conf`. The common mistake is to pass through only the exporter-oriented keys (`OTEL_PHP_AUTOLOAD_ENABLED`, `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_LOG_LEVEL`) and omit the kill switches `OTEL_SDK_DISABLED` and `OTEL_PHP_DISABLED_INSTRUMENTATIONS`. Those two then reach CLI processes (`docker exec`, queue workers) but are stripped from FPM workers, so the intended disable guard silently applies only to the CLI path while the HTTP path keeps emitting spans. Cross-check the Dockerfile's `printf`/`env[]` block against the docker-compose service env list and ensure every `OTEL_*` key set in compose also appears in `www.conf`.
