---
date: 2026-08-07
keywords: ["laravel", "eloquent", "n+1", "batch-load", "whereIn"]
trigger-on: ["eloquent-batch-load-foreach", "n1-findOrFail-in-loop", "whereIn-keyBy"]
---

## Batch-load with whereIn+keyBy to truly eliminate N+1, not just reduce it

Adding `->with()` inside a `foreach` loop still produces N database round-trips (one per iteration) even though each trip loads fewer sub-queries. The correct fix is to collect all IDs first, run a single `whereIn('id', $ids)->with([...])->get()->keyBy('id')` before the loop, then look up each model from the pre-loaded collection. This reduces N queries to 1. Preserve `findOrFail` semantics with `$models[$id] ?? throw new ModelNotFoundException()`.
