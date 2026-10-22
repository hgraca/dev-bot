---
date: 2026-10-22
keywords: ["laravel", "nova", "openspout", "composer", "php-version"]
trigger-on: ["nova-upgrade", "php-version-upgrade"]
---

## Nova 4 caps PHP at 8.1 through fast-excel and openspout

A service on Nova 4 cannot `composer install` on PHP 8.2 or newer, and no targeted package update escapes it. The constraint chain is:

```
laravel/nova 4.12.14
  └─ rap2hpoutre/fast-excel ^3.2|^4.1   → v4.1.0 (locked)
       └─ openspout/openspout ^3
            └─ every 3.x requires php ~7.3|~7.4|~8.0|~8.1
```

Nova 5 is the way out: it requires `openspout ^4.24`, `inertiajs/inertia-laravel ^1.3|^2|^3` and `illuminate/* ^10.48|^11.44|^12|^13` — which means Laravel 11+ comes with it, so a Nova 4 service on an old Laravel needs a framework migration to reach a patched PHP.

Two Composer details that mislead during this work:

- `laravel/nova` metadata resolves **anonymously** from `nova.laravel.com/p2/laravel/nova.json`, so `composer update` succeeds locally without credentials. Only the dist download needs the entitlement.
- When the licence does not cover the requested release, the dist download fails with **HTTP 402 Payment Required**, not 401/403 — it reads like an auth failure but is an entitlement failure, and only a licence renewal fixes it. Versions are visible in the repo metadata, so pinning can be checked before pushing.
