---
date: 2026-08-31
keywords: ["laravel", "cache", "atomic", "lock", "single-use"]
trigger-on: ["laravel-cache-pull-atomicity"]
---

## `Cache::pull()` is not atomic — guard single-use tokens with a cache lock

Laravel's `Cache::pull($key)` is a read-then-delete (get + forget) implemented as two operations, so two concurrent requests can both read the same value before either deletion lands. For single-use semantics (e.g. a one-time correlation token consumed at a CSRF-exempt endpoint), serialize consumers with a cache lock:

```php
$lock = Cache::lock('token_consume_lock:' . $token, 10);
if (!$lock->get()) {
    return null; // another request is consuming this token
}
try {
    return Cache::pull('token:' . $token);
} finally {
    $lock->release();
}
```

Driver-agnostic (works on Redis in prod and array/file in tests). An alternative is Redis GETDEL, but that is driver-specific and breaks the test env.
