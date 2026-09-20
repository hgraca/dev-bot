---
date: 2026-09-16
keywords: ['mariadb', 'explain', 'derived-table', 'lateral-derived', 'optimizer']
trigger-on: ['mariadb-explain', 'mariadb-derived-table', 'query-plan-validation']
---

## EXPLAIN on toy data picks a different plan than production — MariaDB decorrelates derived tables

Running `EXPLAIN` against a local dev table holding a handful of rows can show a plan production will never use, so a performance claim built on it is worthless. Concretely: `select ... from drivers left join (select driver_id, count(*) ... from trip_transports inner join trips ... group by driver_id) d ...` on 7 rows planned as `trip_transports` `type: ALL` with `Using temporary; Using filesort` — looking like a table-wide aggregation — while the identical query on production (2.1M rows) planned as `select_type: LATERAL DERIVED` with `ref` on `trip_transports_driver_id_foreign`. MariaDB 11.4 decorrelates the derived table and pushes the outer `drivers.id` into it, so it never scans the table; with skewed or absent statistics the optimiser simply falls back to the naive plan. Re-derive any query-performance conclusion against production-scale data before writing it into a commit message, and prefer `ANALYZE FORMAT=JSON` (`r_total_time_ms`, `r_rows`, `r_engine_stats.pages_accessed`) over row-count estimates when you need real cost.
