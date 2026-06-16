---
name: find-db-performance-issues
description: Find database issues (full table scans, slow queries, N+1, app anti-patterns, lock contention, hardware limitations) driving DB load, using SigNoz
---

Use the SigNoz MCP tools to find every category of database issue in production, then produce a delegation-ready inventory. Categorize each finding as exactly one of the categories below.

## 1. Establish the load profile

Query these metrics with `deployment.environment = 'production'`, 24h window:

**Query-driven vs concurrency vs resource-bound**

- `aws_rds_cpuutilization_average` — sustained ~100% = CPU ceiling (hardware).
- `mysql_global_status_handlers_total` grouped by `handler` — `read_rnd_next` (full scans) vs `read_next` (range) vs `read_key` (point). `read_rnd_next` dominating = full-scan-driven.
- `mysql_global_status_innodb_buffer_pool_reads` vs `..._read_requests` — hit ratio <99% = working set exceeds RAM.
- `mysql_global_status_innodb_buffer_pool_wait_free` (rate) — waiting for a free page = buffer pool too small.

**Lock contention**

- `mysql_global_status_innodb_row_lock_waits` (rate), `innodb_row_lock_time`, `innodb_row_lock_current_waits` — transactions blocking each other.
- `mysql_global_status_innodb_deadlocks` (rate) — deadlock rate.
- `mysql_global_status_innodb_history_list_length` — growing = long-running transactions holding the purge back.

**Query-plan / temp signals**

- `mysql_global_status_select_scan` (rate) — full-scan queries/sec.
- `mysql_global_status_select_full_join`, `select_full_range_join` (rate) — cross/full joins and range-check joins (no usable join index).
- `mysql_global_status_created_tmp_disk_tables` vs `created_tmp_tables`, `sort_merge_passes` — temp-table / disk-sort spill.

**Resource ceilings (hardware)**

- Connections: `aws_rds_database_connections_average` vs `mysql_global_variables_max_connections`; `mysql_global_status_threads_created` (rate) = churn; `aborted_clients` / `aborted_connects`.
- Memory: `aws_rds_freeable_memory_average` near 0.
- IOPS: `aws_rds_read_iops_average` / `aws_rds_write_iops_average` near limit.
- Disk: `aws_rds_free_storage_space_average` near 0.
- Replication: `mysql_global_status_slave_running`, `slaves_connected`, and `mysql_slave_status_seconds_behind_master` if exposed.

## 2. Rank queries

- **By total DB time (CPU)**: `signoz_aggregate_traces` aggregation `sum`, `aggregateOn = durationNano`, `groupBy = service.name, db.query.text`, filter `db.query.text != '' AND deployment.environment = 'production'`, `timeRange = 24h`, `limit = 60`, order `sum(durationNano) desc`.
- **By latency (slow queries)**: aggregation `avg`, `aggregateOn = durationNano`, same groupBy/filter, order `avg(durationNano) desc`. Also `p99` for tail latency.
- **By frequency (N+1)**: aggregation `count`, same groupBy/filter, order `count() desc`.

## 3. Detect N+1

- Same point-lookup text executed ~1M+ times/day (`select * from X where id = ? limit 1`, `where <fk> = ?`).
- `count` grouped by `traceID, db.query.text` — same query text repeated >3× within a single trace.
- `count` grouped by `traceID` — traces with >10 DB spans.

## 3b. Detect application-level anti-patterns (inspect `db.query.text`)

Aggregate `count` grouped by `db.query.text` with these filters, and flag the offenders:

- **Over-fetching** — `db.query.text LIKE 'select *%'` (fetches whole wide rows when a few columns would do).
- **Existence/count check** — `db.query.text CONTAINS 'count(*)'` (a `COUNT(*)` that could be `EXISTS` / `limit 1` / cached).
- **Redundant ORM predicate** — `db.query.text CONTAINS ' is not null'` or `db.query.text CONTAINS ' in (?)'` with a single value (Eloquent's `whereNotNull`/single-element `whereIn` output).
- **Non-sargable predicate** — `db.query.text CONTAINS 'DATE('` / `'DATE_FORMAT('` / `'FIND_IN_SET('` / `"LIKE '%"` (function on a column defeats the index).
- **Connection churn** — `db.query.text LIKE 'SET %'` or `db.query.text LIKE 'use %'` (per-connection session setup = no pooling).
- **Single-row write** — `db.query.text LIKE 'insert into % values (?)'` (single-row inserts in a loop → bulk INSERT).
- **Missing cache** — a static reference lookup (countries/currencies/airports/settings) re-run ~1M+×/day.

## 4. Classify each finding

| Category                            | Signals / causes                                                                                                                                                                                                          | Suggested fix                                                     |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| **Full table scan**                 | `read_rnd_next` dominant; non-sargable (`DATE(col)`, `DATE_FORMAT(col)`, `FIND_IN_SET`, `LIKE '%…%'`), `IS NULL`, spatial (`ST_*`) without spatial index, unindexed columns, correlated subqueries, unfiltered `count(*)` | add index / rewrite predicate / cache / prune table               |
| **Slow query**                      | high `avg` / `p99` duration; wide avg↔p99 gap; large result set; sort/temp-table spill                                                                                                                                    | add covering index, rewrite, paginate/chunk, shrink result set    |
| **N+1**                             | same point-lookup ~1M+×/day; repeated `db.query.text` per trace; many DB spans per trace                                                                                                                                  | eager-load, batch `whereIn`, cache reference data                 |
| **Over-fetching**                   | `select *` on wide tables, no `LIMIT`                                                                                                                                                                                     | select needed columns, paginate                                   |
| **Redundant query / missing cache** | same static lookup re-run per request; `count(*)` existence checks; redundant ORM predicates (`is not null`, single-value `IN`)                                                                                           | cache reference data, `EXISTS`, batch `whereIn`                   |
| **Write inefficiency**              | single-row `insert … values (?)` in a loop                                                                                                                                                                                | bulk INSERT / chunk                                               |
| **Lock contention / deadlock**      | `innodb_row_lock_waits`↑, `innodb_row_lock_current_waits`>0, `innodb_deadlocks`>0, wide avg↔p99 gap                                                                                                                       | shorten transactions, reorder lock acquisition, avoid table locks |
| **Bad join plan**                   | `select_full_join`↑, `select_full_range_join`↑                                                                                                                                                                            | add join-key indexes, rewrite join order                          |
| **Long-running transaction**        | `innodb_history_list_length` growing                                                                                                                                                                                      | commit sooner, split long transactions                            |
| **Temp table / disk sort**          | `created_tmp_disk_tables`↑, `sort_merge_passes`↑                                                                                                                                                                          | index GROUP BY / ORDER BY / DISTINCT                              |
| **Connection churn / pool misuse**  | `threads_created` (rate)↑, `aborted_clients`↑, per-connection `SET …` / `use …` statements                                                                                                                                | connection pooling, persistent connections                        |
| **Buffer pool pressure**            | `innodb_buffer_pool_wait_free`↑, hit ratio <99%                                                                                                                                                                           | larger buffer pool / more RAM                                     |
| **Replication lag**                 | `seconds_behind_master`↑                                                                                                                                                                                                  | tune replica / offending writes                                   |
| **Hardware / resource**             | CPU ~100%; connections near `max_connections`; freeable memory ~0; IOPS at limit; free disk ~0                                                                                                                            | resize instance / more vCPU / provisioned IOPS / prune            |

## 5. Write backlogs + report

- For each application with query-related findings, create a backlog file in `.agents/memory/work/active/` under that application's repo (e.g. `~/Development/Get-e/core`, `~/Development/Get-e/hotels-api`), one per application, all in parallel. The user will deliver each backlog to the owning project.
- Hardware / resource / lock / replication findings do not belong to an app repo — list them in a separate section of the report instead.
- Print a **global simplified report directly to the user**: a summary table grouped by category, each row = app · query (or signal) · category · evidence · one-line fix.
