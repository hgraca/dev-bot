---
date: 2026-06-23
keywords: ["laravel", "opentelemetry", "config-cache", "serialization"]
trigger-on: ["otel-logging-config", "laravel-config-cache", "otel-globals-in-config"]
---

## OTEL Globals::loggerProvider() in config breaks config:cache

`Globals::loggerProvider()` (and similar OTEL Globals methods like `tracerProvider()`, `meterProvider()`) return SDK objects that lack `__set_state()`, making them non-serializable. When used inline in a Laravel config file (e.g., `config/logging.php`), `php artisan config:cache` fails with `Call to undefined method OpenTelemetry\SDK\Logs\LoggerProvider::__set_state()`. Fix: create a thin wrapper class that calls `Globals::loggerProvider()` in its constructor (at request time) rather than in the config file (at compile time). Reference only serializable class strings in config files. Pattern: `class LazyOtelHandler extends OtelHandler { public function __construct(...) { parent::__construct(Globals::loggerProvider(), ...); } }` then use `LazyOtelHandler::class` in config.
