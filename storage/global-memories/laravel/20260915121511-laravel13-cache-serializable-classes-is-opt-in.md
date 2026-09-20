---
date: 2026-09-15
keywords: ["laravel", "cache", "serializable_classes", "unserialize", "upgrade"]
trigger-on: ["laravel13-upgrade", "cache-unserialize-hardening"]
---

## Laravel 13's cache unserialization hardening is opt-in via application config, not a framework default

Laravel 13 added `cache.serializable_classes` to guard against PHP deserialization gadget chains, but the guard only applies when the key is present. `Illuminate\Cache\CacheManager` resolves it as `config('cache.serializable_classes') ?? null`, and the stores pass `allowed_classes` to `unserialize()` only when that value is not null — so an application whose `config/cache.php` lacks the key silently keeps the old permissive behaviour even after upgrading. The framework's own shipped `config/cache.php` does not contain the key either; only the application skeleton sets it, to `false`. Confirm the effective state with `config('cache.serializable_classes')` (null means no hardening) and add `'serializable_classes' => false` to adopt it, or an explicit allow-list when the app legitimately caches objects. Anything not allowed becomes `__PHP_Incomplete_Class` on read, and object entries cached before the change become unreadable — so deploy the hardening together with a cache clear.
