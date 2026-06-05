---
date: 2026-08-03
keywords: ["laravel", "eloquent", "relationLoaded", "n+1", "accessor"]
trigger-on: ["eloquent-relation-query", "get-latest-relation", "model-accessor"]
---

## Use relationLoaded in accessor methods to skip DB when relation is pre-loaded

When a model has an accessor method that queries a relation (e.g. `getLatestFoo()`), check `$this->relationLoaded('relationName')` first. If the relation is already in memory — either from `with()` eager-loading or an explicit `setRelation()` — use it instead of hitting the database.

```php
public function getLastPositionUpdate(): ?PositionUpdate
{
    if ($this->relationLoaded('positionUpdates')) {
        return $this->positionUpdates->isNotEmpty()
            ? $this->positionUpdates->sortByDesc('id')->first()
            : null;
    }
    return $this->positionUpdates()->latest('id')->first();
}
```

Callers can then inject a pre-loaded relation before the accessor runs:

```php
$trip->setRelation('positionUpdates', collect([$positionUpdate]));
// $trip->getLastPositionUpdate() now returns from memory, no DB query
```

This is especially useful when an Eloquent observer or downstream transformer calls the accessor for a model that was just saved — the latest data is already in memory.
