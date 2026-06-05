---
date: 2026-08-05
keywords: ["laravel", "eloquent", "relationLoaded", "eager-load", "take1"]
trigger-on: ["relationLoaded-performance-optimization", "eager-load-with-constraints", "get-latest-relation"]
---

## relationLoaded() with general relation name collides with eager-loads using take(1)

When using `relationLoaded('relationName')` in an accessor to skip a DB query for the latest record, using a general relation name (e.g. `positionUpdates`) is dangerous if any caller eager-loads that same relation with `->take(1)` and no `orderBy`. The loaded collection contains an arbitrary record, not necessarily the latest — so the accessor silently returns wrong data.

Fix: use a dedicated relation name (e.g. `latestPositionUpdate`) set only by the code injecting the in-memory cache. This isolates the optimization path from general eager-loads with constraints. In the processor: `$trip->setRelation('latestPositionUpdate', $update)`. In the accessor: `if ($this->relationLoaded('latestPositionUpdate')) { return $this->latestPositionUpdate; }`.
