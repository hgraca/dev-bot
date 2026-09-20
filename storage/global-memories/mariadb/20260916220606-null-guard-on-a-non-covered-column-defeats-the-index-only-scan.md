---
date: 2026-09-16
keywords: ['mariadb', 'index-only-scan', 'covering-index', 'count', 'null-guard']
trigger-on: ['mariadb-index-only-scan', 'mariadb-count-group-by']
---

## A NOT NULL guard (or count(col)) on a non-covered column silently defeats the index-only scan

A `group by` count can run index-only and be an order of magnitude cheaper than the same count with one extra predicate — if that predicate references a column the chosen index does not contain. Measured on MariaDB 11.4 with `trip_transports` (2.39M rows) grouped by `driver_id` for 1,332 drivers: `count(*)` restricted to those drivers used the `driver_id` secondary index index-only at 4,109 pages / 23.5 ms, while adding `where trip_id is not null` (trip_id is not part of that index) dropped the `using_index` flag and forced clustered-row lookups — 154,443 pages / 130.3 ms, a 5.6x regression for a predicate that filtered nothing (0 of 2,390,738 rows were NULL). `count(trip_id)` costs the same, since it must read the column too. Before adding a defensive predicate to a hot aggregate, check the plan for `using_index`; if the predicate is not index-covered, either drop it and document the assumption, or add a composite index that covers it.
