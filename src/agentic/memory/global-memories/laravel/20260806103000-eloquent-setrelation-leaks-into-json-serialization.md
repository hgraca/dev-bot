---
date: 2026-08-06
keywords: ["laravel", "eloquent", "serialization", "pusher", "n+1"]
trigger-on: ["eloquent-serialization", "pusher-payload", "setRelation-gotcha"]
---

## Eloquent setRelation() / eager-loads leak into JSON serialization

When an Eloquent model is serialized (e.g. JSON-encoded for Pusher, HTTP responses, or queue payloads), ALL loaded relations — including those set via `setRelation()` or eager-loaded with `with()` — are included in the output. This can silently blow past transport limits (Pusher's 10KB payload cap, queue message size limits, etc.) when N+1 optimizations add eager-loads that were not previously loaded. The fix: use `$model->attributesToArray()` to exclude relations from serialization, or explicitly construct the output array without the model object itself. The `setRelation()` call stays (needed for downstream code to avoid DB queries), but the serialization boundary must be controlled.
