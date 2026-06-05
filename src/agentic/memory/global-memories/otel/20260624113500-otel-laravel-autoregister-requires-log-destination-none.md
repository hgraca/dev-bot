---
date: 2026-06-24
keywords: ["otel", "laravel", "opentelemetry", "memory-exhaustion", "log-watcher"]
trigger-on: ["otel-auto-laravel", "OTEL_PHP_LOG_DESTINATION", "opentelemetry-php-log-destination", "laravel-memory-exhaustion-otel"]
---

## OTEL auto-laravel watchers cause memory exhaustion without OTEL_PHP_LOG_DESTINATION=none

When `opentelemetry-auto-laravel` is installed, its `_register.php` auto-registers `LogWatcher` and `ExceptionWatcher` — these listen to every `MessageLogged` event and push data into OTEL spans. The `_register.php` does NOT check `OTEL_PHP_AUTOLOAD_ENABLED`; it only checks for the `opentelemetry` extension and `Sdk::isInstrumentationDisabled()`. Without `OTEL_PHP_LOG_DESTINATION=none`, the OTEL SDK defaults its internal diagnostic logging to `error_log()`, adding overhead that compounds with span data accumulation from the watchers. Over many log events (especially with large exception contexts), PHP memory exhausts at the 512MB limit. Always set `OTEL_PHP_LOG_DESTINATION=none` in production env files, regardless of whether a dedicated OTEL logging channel exists in Laravel's config.
