---
date: 2026-08-18
keywords: ["laravel", "eloquent", "where", "null", "is-null"]
trigger-on: ["eloquent-where-null", "where-nullable-value"]
---

## Eloquent where('column', null) emits IS NULL, not a null comparison

`Model::where('column', $nullableValue)` compiles to `WHERE column IS NULL` when `$nullableValue` is `null` (Laravel treats a null value as an `IS NULL` predicate). If the column is `NOT NULL` (e.g. `airports.iata`), the query returns no rows and can't use an index — it degenerates into a full scan. This bit the Booking.com `DescriptorDtoFactory::fromLocationDto()`, which passed `$locationDto->getIata()` (nullable) straight into `where('iata', ...)`, producing a `select * from airports where iata is null limit 1` full scan ~900K times/day. Fix: guard `if ($value !== null)` before querying, or use `whereNotNull`/`whereNull` explicitly when null really is the intent.
