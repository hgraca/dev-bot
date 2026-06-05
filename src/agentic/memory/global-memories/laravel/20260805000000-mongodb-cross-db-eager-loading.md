---
date: 2026-08-05
keywords: ["laravel", "mongodb", "eloquent", "eager-loading", "n-plus-one"]
trigger-on: ["mongodb-eloquent-eager-load", "cross-database-eager-load"]
---

## MongoDB Eloquent eager-loading of SQL relations may silently fail

When a MongoDB model (extending `MongoDB\Laravel\Eloquent\Model`) has `belongsTo` relations to SQL models and you call `loadMissing()` / `load()` on a collection of those MongoDB models, the cross-database eager-load may not work reliably. The `loadMissing` guard `if ($collection instanceof DatabaseCollection)` might pass, but the resulting eager-load query may not actually execute across database connections. Always verify with SigNoz trace analysis after adding eager-loads. If `load()` doesn't reduce queries, fall back to manual batch loading: collect foreign key IDs from the MongoDB models and run a single SQL `whereIn` query, then map results back.
