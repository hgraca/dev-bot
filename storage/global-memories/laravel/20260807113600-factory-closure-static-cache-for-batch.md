---
date: 2026-08-07
keywords: ["laravel", "eloquent", "factory", "static-cache"]
trigger-on: ["eloquent-factory-static-cache", "factory-count-n-performance"]
---

## Cache expensive factory defaults with static variable in closure

Even after wrapping a DB query in `fn() =>` to defer evaluation for RefreshDatabase, a factory closure still executes per-model when using `count(n)`. To avoid n queries, cache the result with `static $cached = null; return $cached ??= Model::all();`. This ensures a single DB round-trip for the entire factory batch. Use a `static function` closure so the static variable is scoped to the closure, not the factory instance.
