---
date: 2026-08-20
keywords: ["laravel", "eloquent", "eager-loading", "exists"]
trigger-on: ["laravel-relation-exists-eager-load"]
---

## `->relation()->exists()` re-queries the DB even when the relation is eager-loaded

Calling `$model->relation()->exists()` (query builder) always issues a fresh `select exists(...)` query, even when `relation` was already eager-loaded via `with('relation')` or `load('relation')`. To read the loaded collection instead, use `$model->relation->isNotEmpty()` (or `->isEmpty()`). Common in N+1 hot paths where a collection is eager-loaded but then re-checked per item with `exists()`.
