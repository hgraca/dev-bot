---
date: 2026-08-20
keywords: ["laravel", "cache", "authorization", "security"]
trigger-on: ["laravel-cache-authz-cross-request"]
---

## Don't cache authorization decisions in the shared cache — use the request store

`Cache::remember()` targets the shared default store (file/redis), so an authorization result (e.g. a resolved account id, a permission check) survives into subsequent requests and can be served stale after access is revoked or the account type changes. For security-sensitive values that must not outlive the request, use the request-scoped store: `Cache::store('request')->rememberForever($key, $fn)` (array driver, per-request). The 1s-TTL "collapse per-request point lookups" pattern is the wrong tool for authz — keep it for cheap idempotent lookups only.
