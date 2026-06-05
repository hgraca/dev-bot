---
date: 2026-08-03
keywords: ["laravel", "eloquent", "observer", "n+1", "setRelation"]
trigger-on: ["eloquent-observer", "position-update-observer", "model-save-with-observer"]
---

## Use setRelation to prevent observer cascade N+1 from re-loading models

When an Eloquent observer's `created`/`updated`/`saved` callback accesses a relation via `$model->relation` that hasn't been pre-loaded, Eloquent lazy-loads it — potentially triggering a fresh DB query for every model save. If the observer does this for N saved models in a loop, it's an N+1 cascade.

**Prevention:** Before `$model->save()`, call `$model->setRelation('relation', $loadedInstance)` to inject the already-fetched related model. When the observer later accesses `$model->relation`, Eloquent returns the pre-set value without hitting the database.

```php
$trip = Trip::with(['points', 'driver'])->first();
// ... process ...
$update = new PositionUpdate(['trip_id' => $trip->id]);
$update->setRelation('trip', $trip);  // observer's $posUpdate->trip won't re-query
$update->save();
```

This is especially critical in hot-path consumers (Kafka, queue workers) where each save triggers observer callbacks that cascade into further lazy loads.
