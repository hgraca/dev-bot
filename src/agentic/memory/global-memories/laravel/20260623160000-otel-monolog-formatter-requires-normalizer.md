---
date: 2026-06-23
keywords: ["laravel", "monolog", "opentelemetry", "formatter"]
trigger-on: ["otel-logging-config", "laravel-otel-monolog"]
---

## OTEL Monolog handler requires NormalizerFormatter, not LineFormatter

Laravel's `LogManager::prepareHandler()` unconditionally calls `$handler->setFormatter()` with `LineFormatter(null, $this->dateFormat, true, true, true)` (last `true` = `includeStacktraces=true`) on every handler that implements `FormattableHandlerInterface` and does not explicitly set a `'formatter'` config key. The `open-telemetry/opentelemetry-logger-monolog` handler's `write()` method does `$formatted['message']` (line 67) — it expects `$formatted` to be an **array** (from `NormalizerFormatter::format()`). When overridden with `LineFormatter`, `format()` returns a **string**, causing `TypeError: Cannot access offset of type string on string`. Fix: explicitly set `'formatter' => \Monolog\Formatter\NormalizerFormatter::class` in the otel channel config. Do NOT use `'formatter' => 'default'` — it does not reliably prevent the override at runtime. Also set `'bubble' => false` on the otel channel since it is always the last handler in LOG_STACK.
