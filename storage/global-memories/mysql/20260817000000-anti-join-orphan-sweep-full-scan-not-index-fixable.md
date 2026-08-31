---
date: 2026-08-17
keywords: ["mysql", "anti-join", "whereDoesntHave", "full-scan", "index"]
trigger-on: ["anti-join", "whereDoesntHave", "not-exists", "orphan-sweep", "left-join-is-null"]
---

## Anti-join orphan sweeps always full-scan the outer table — not fixable by an index or a LEFT JOIN

A query that finds rows with _no_ related record (Eloquent `whereDoesntHave` → `NOT EXISTS`, or `LEFT JOIN ... WHERE x.id IS NULL`) must examine every row of the outer table, so MySQL always full-scans that table no matter what indexes exist. Adding an index on the inner join column — even when it is already the primary key — only speeds the per-row probe, not the scan. Rewriting `NOT EXISTS` to `LEFT JOIN ... IS NULL` does not help either: the cost is identical, and the optimizer merely swaps a materialized subquery for an `eq_ref` with a `Not exists` extra. Verified on `hotels-api`: the hourly `BookingEstimationExchangeRateCatchAll` sweep (`contract_booking_projections` anti-joined against `contract_booking_projection_exchange_rates.projection_uuid`, both already primary keys) averaged 21s, and neither form changed the plan. The only real fixes are to scope the outer query by an indexed column (e.g. `created_at`) so the full scan becomes an index range scan, to denormalize a sparse "needs X" flag, or to run the sweep less often/off-peak.
