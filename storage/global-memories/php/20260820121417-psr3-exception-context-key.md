---
date: 2026-08-20
keywords: ["php", "psr-3", "logging", "exception", "stack-trace"]
trigger-on: ["psr3-exception-context-key"]
---

## PSR-3 log the exception object, not just getMessage()

PSR-3 reserves the `exception` context key: handlers extract the full stack trace from it. Logging only `['error' => $e->getMessage()]` produces near-useless diagnostics in defensive code paths designed to absorb failures silently (e.g. a telemetry wrapper that must never crash the app). When catching a Throwable and logging it, always pass `'exception' => $e` in the context array alongside any message key. Applies to every catch block that logs — audit your catch sites for contexts that omit it.
