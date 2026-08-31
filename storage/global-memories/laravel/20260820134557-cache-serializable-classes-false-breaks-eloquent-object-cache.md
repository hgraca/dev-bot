---
date: 2026-08-20
keywords: ["laravel", "cache", "serializable_classes", "eloquent"]
trigger-on: ["laravel-cache-eloquent-object", "serializable-classes"]
---

## Caching Eloquent objects in a store with serializable_classes=false crashes on read

With Laravel's `serializable_classes => false` cache config (a common hardening default, as in GET-E's `config/cache.php`), `Cache::remember()` of a live Eloquent model serializes the object, and on a cache hit `unserialize($value, ['allowed_classes' => false])` returns `__PHP_Incomplete_Class`; any subsequent method call (e.g. `getAuthIdentifier()`) throws. Only cache primitives/arrays in the default store. To dedupe an object use the `request` array store (`serializesValues = false`, no serialization), a dedicated store whose `serializable_classes` allow-lists the class, or cache the attribute array and rehydrate.
