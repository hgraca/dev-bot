---
date: 2026-08-17
keywords: ["mysql", "in-subquery", "full-scan", "index", "union"]
trigger-on: ["in-subquery", "or-index-merge", "query-optimization", "literal-in-list"]
---

## A literal `WHERE id IN (list)` uses the index; `IN (subquery)` can trigger a correlated EXISTS full scan

On MariaDB, `WHERE id IN (v1, v2, …)` is resolved as a primary-key range scan, but `WHERE id IN (SELECT …)` can be planned as a semi-join with a correlated `EXISTS` that re-executes the subquery per outer row and full-scans the driving table (seen in `EXPLAIN ANALYZE` as `attached_condition: <in_optimizer>(id, <exists>(subquery))`). An `OR` of index-unfriendly branches (e.g. `point_type='A' AND point_id=x OR point_type='B' AND point_id IN (subquery)`) has the same effect. Fix: resolve the matching ids in a separate `UNION` of two index-driven queries, then filter the main query with a literal `WHERE id IN (...)`. On the transfers pricing engine this took the route-resolution step from a 48k-row full scan (~450ms, and the whole query from ~3.9s) to ~15ms of index seeks plus a ~20-40ms PK-range join.
