---
date: 2026-11-26
keywords: ["laravel", "monolog", "log-channel", "opentelemetry"]
aliases: ["LOG_CHANNEL=silent", "emergency logger recursion", "laravel.log grows until the disk is full"]
trigger-on: ["laravel-log-channel", "opentelemetry-laravel-logging"]
---

## An undefined LOG_CHANNEL turns every log event into an infinite disk-filling loop

When `LOG_CHANNEL` names a channel that `config/logging.php` does not define (a template shipping `silent` while only `stack`, `single`, `daily`, `stderr` and `null` exist), `LogManager::resolve()` throws `InvalidArgumentException: Log [silent] is not defined`; Laravel's emergency logger then appends that stack trace to `storage/logs/laravel.log`. With `open-telemetry/opentelemetry-auto-laravel` installed the amplification is unbounded: its `LogWatcher` calls `getLogger()` for the same channel on every log event, throws again, and emergency-logs again — a recursion that observed ~17 MB/s and 62 GB before the disk filled. Any process that merely boots the app triggers it, so Rector or Larastan runs inside a dev container silently fill the host disk through a root-owned `storage/logs` bind mount. Fix the value (`null` discards, `stderr` keeps output), or override per run with `-e LOG_CHANNEL=null` — the real environment wins over `.env`, which phpdotenv does not overwrite — and mount a size-capped tmpfs over `storage/logs` so a bad run cannot reach the host.
