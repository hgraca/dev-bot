---
date: 2026-09-18
keywords: ["php", "composer-dependency-analyser", "opentelemetry", "static-analysis"]
trigger-on: ["composer-dependency-analyser", "shipmonk-analyzer", "otel-packages"]
---

## composer-dependency-analyser reports auto-instrumentation packages as unused and fails CI

`shipmonk-rnd/composer-dependency-analyser` only sees symbols referenced from scanned code, so packages whose only job is registration through the PHP extension or the composer autoloader (OpenTelemetry's `opentelemetry-auto-*`, `exporter-otlp`, `sdk`, `php-http/guzzle7-adapter`) are reported as `UNUSED_DEPENDENCY` and turn `make test` red even though the application works. Silence them per package in `composer-dependency-analyser.php` with `->ignoreErrorsOnPackage('<name>', [ErrorType::UNUSED_DEPENDENCY])`; the platform requirement needs its own method, `->ignoreErrorsOnExtension('ext-opentelemetry', [...])`, because `ignoreErrorsOnPackage` does not cover `ext-*` entries.
