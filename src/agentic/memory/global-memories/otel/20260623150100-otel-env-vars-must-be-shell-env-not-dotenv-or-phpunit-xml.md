---
date: 2026-06-23
keywords: ["otel", "opentelemetry", "php", "phpunit", "segfault"]
trigger-on: ["otel-auto-laravel", "phpunit-segfault", "opentelemetry-php-extension", "premature-end-of-php-process"]
---

## OTEL_SDK_DISABLED and OTEL_PHP_DISABLED_INSTRUMENTATIONS must be shell env vars, not `.env.phpunit` or `phpunit.xml`

The OpenTelemetry PECL extension (opentelemetry-1.2.1) and its PHP-level SDK (`open-telemetry/opentelemetry-auto-laravel` via `autoload.files`) install C-extension hooks at Composer autoload time — BEFORE PHPUnit processes `phpunit.xml` `<env>` tags and BEFORE Laravel loads `.env.phpunit`. If `OTEL_SDK_DISABLED` and `OTEL_PHP_DISABLED_INSTRUMENTATIONS` are set only in `.env.phpunit` or `phpunit.xml`, the hooks install unconditionally and cause segfaults during Laravel Pipeline closure execution (presents as `Fatal error: Premature end of PHP process`). Fix: set these vars in the OS shell environment via `export OTEL_SDK_DISABLED=true` and `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all` before running PHP. In a Makefile-driven Docker setup, use target-specific exports: `..unit: export OTEL_SDK_DISABLED := true`. See also SUPERSEDED note about `.env.phpunit` approach that doesn't work for CLI PHP.
