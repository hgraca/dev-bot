---
date: 2026-06-23
keywords: ["laravel", "otel", "opentelemetry", "monolog", "formatter"]
trigger-on: ["otel-monolog-handler", "laravel-logging-config"]
---

## Laravel LogManager::prepareHandler overrides OTEL handler formatter causing memory exhaustion

Laravel's `LogManager::prepareHandler()` calls `$handler->setFormatter(new LineFormatter(null, null, true, true, true))` on EVERY handler that doesn't explicitly set a formatter in its channel config. The last `true` is `includeStacktraces=true`, which causes Monolog to stringify exception stack traces for every log record. When the OTEL `Handler` (which extends `AbstractProcessingHandler`) receives a log with an exception, the LineFormatter converts the stack trace to a string via `stacktracesParser()` (`vendor/monolog/monolog/src/Monolog/Formatter/LineFormatter.php:310`), consuming enormous memory and crashing PHP-FPM with `Allowed memory size exhausted`.

Fix: set `'formatter' => 'default'` in the OTEL channel config to tell Laravel "skip the override, use the handler's native formatter". The OTEL handler's built-in `NormalizerFormatter` handles formatting efficiently without stringifying stack traces. Also set `'bubble' => false` since the OTEL handler is always last in the LOG_STACK.
