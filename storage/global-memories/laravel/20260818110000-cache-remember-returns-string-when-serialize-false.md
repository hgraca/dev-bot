---
date: 2026-08-18
keywords: ["laravel", "cache", "remember", "serialize", "redis"]
trigger-on: ["cache-remember-serialize-false", "cache-typed-return"]
---

## Cache::remember returns strings when the store has serialize: false

With Laravel 11's `serialize: false` on a cache store (the default for redis/database/file stores), `Cache::remember()` / `Repository::remember()` stores the callback's return value as a raw string and returns it as a string, not the original PHP type. A method declared with a typed `: int` return throws `TypeError: Return value must be of type int, string returned` on the first cache hit (the initial miss returns the callback's real int, so the failure appears only after the value is cached). Fix: cast the retrieved value explicitly, e.g. `(int) $cache->remember($key, $ttl, fn (): int => DB::table(...)->count())`. Note scalars like `0` and `false` also round-trip as strings (`"0"`, `""`), so always cast to the expected type rather than relying on `is_null()` misses alone.
