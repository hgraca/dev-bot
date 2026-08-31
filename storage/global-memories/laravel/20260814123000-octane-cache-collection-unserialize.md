---
date: 2026-08-14
keywords: ["laravel", "octane", "cache", "collection", "unserialize"]
trigger-on: ["laravel-octane-cache", "cache-remember-collection"]
---

## Don't cache a Collection object — Octane can't unserialize it

`Cache::remember($key, $ttl, fn () => $collection)` serializes the whole `Illuminate\Support\Collection`. With `CACHE_STORE=database` (or redis/file) under Octane, a cache hit unserializes it before the `Collection` class is autoloaded, so the next method call throws "tried to call a method on an incomplete object". Symptom is silent and asymmetric: the first request works (returns the live object), the second request 500s or returns empty. Fix: cache a plain array and re-wrap after retrieval — `collect(Cache::remember($key, $ttl, fn (): array => $rows->map(...)->values()->all()))`. Arrays serialize cleanly and need no class autoload on unserialize.
