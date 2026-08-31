---
date: 2026-08-21
keywords: ["laravel", "cache", "array-store", "queue", "kafka"]
trigger-on: ["laravel-array-cache-per-process", "request-cache-long-running"]
---

## The `array`/`request` cache store is per-process, not per-request — clear it in long-running processes

Laravel's `array` cache driver (and any store backed by it, like a `request` store) is an in-memory store scoped to the PHP process, not to a request. Under PHP-FPM it is "per-request" only because each request is a fresh process. In long-running processes the array persists across units of work unless explicitly cleared: Laravel's `queue:work` clears it via a `JobProcessing` listener (`Cache::store('request')->clear()`), but custom long-running loops (Kafka consumers, `while(true)` commands, Octane) do not — so a cached SELECT from one message/job is served stale by the next. When introducing a per-request cache store, verify every long-running entry point clears it between messages, or clear it at the top of each message-processing block.
