---
date: 2026-06-26
keywords: ["laravel", "monolog", "sentry", "memory-limit", "logging"]
trigger-on: ["laravel-logging-config", "LOG_STACK", "monolog-stack-channel", "php-memory-exhaustion"]
---

## LOG_STACK=null causes cascading PHP memory exhaustion in production

Setting `LOG_STACK=null` in `.env.production` with Laravel's default `'ignore_exceptions' => false` on the stack channel causes cascading memory exhaustion. When any error occurs, Monolog's stack handler bubbles the exception up as a PHP error (because `ignore_exceptions` is false). Sentry then captures the error with full context (stack traces, SQL queries with bindings, breadcrumbs). If the error payload is large (or if serialization hits a circular reference), the PHP process exceeds its memory_limit (default 512MB) — first in Monolog's LineFormatter, then in Sentry's HttpClient. The pod then crashes with "Allowed memory size exhausted" in both Monolog and Sentry. Fix: Always set `LOG_STACK=stderr` (or another real channel) in production. The `null` channel is a NullHandler that discards everything — there is no fallback.
