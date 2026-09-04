---
name: devbot:find-db-performance-issues
description: Find database issues (runaway/long-running queries, full table scans, slow queries, N+1, app anti-patterns, lock contention, hardware limitations) driving DB load — starting from a live processlist investigation of the DB, then SigNoz
---

Find every category of database issue in production, then produce a delegation-ready inventory. Categorize each finding as exactly one of the categories below.

**Start with §0 (live DB investigation) before any SigNoz work.** SigNoz digest/trace views only show _completed_ statements — a query that has run for days without finishing (optimizer spin, runaway scan) is invisible to them yet can be the entire CPU load.

## 0. Investigate the live DB first — running processes, duration, repetition, resource consumption

Access is **direct SQL through the JetBrains MCP database tools** (not SigNoz): `list_database_connections` → pick the read-only production connection (e.g. `prod-mariadb-read`), then `execute_sql_query` on it. The RDS instance is usually shared and hosts several applications' schemas (`gete_prod`, `drivers`, `hotels`, `audit_log`, `positioning_*`, …). The processlist is instance-wide — **attribute findings by schema/user**. Keep the connection read-only: report live thread IDs as kill candidates for a write connection; never kill from here.

### 0.1 Running processes and duration

```sql
-- all active (non-sleep) threads, longest first
SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(REPLACE(INFO,'\n',' '),200) AS info
FROM information_schema.PROCESSLIST
WHERE COMMAND <> 'Sleep' AND ID <> CONNECTION_ID()
ORDER BY TIME DESC;
```

- A long `TIME` in an active state (`Query`/`Execute` + `Sending data`, `Statistics`, `executing`) = a long-running statement. `Sleep` threads are idle pools — ignore.
- Sample twice a few seconds/minutes apart: `TIME` advancing and the same thread still present = genuinely running, not a snapshot artefact.
- The processlist `INFO` is truncated — pull the exact statement and progress from performance_schema:

    ```sql
    SELECT es.THREAD_ID, t.PROCESSLIST_ID, LEFT(es.SQL_TEXT,500) AS sql_text,
           ROUND(es.TIMER_WAIT/1e12,1) AS sec, es.ROWS_EXAMINED, es.ROWS_SENT
    FROM performance_schema.events_statements_current es
    JOIN performance_schema.threads t ON t.THREAD_ID = es.THREAD_ID
    WHERE es.SQL_TEXT IS NOT NULL
    ORDER BY es.TIMER_WAIT DESC;
    ```

### 0.2 Is the thread burning CPU or blocked?

```sql
SELECT EVENT_NAME, COUNT_STAR, ROUND(SUM_TIMER_WAIT/1e12,1) AS wait_sec
FROM performance_schema.events_waits_summary_by_thread_by_event_name
WHERE THREAD_ID = <thread_id> AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC;
```

- **Near-zero waits while the statement timer keeps advancing = on-CPU** (optimizer/statistics spin, scan compute). This is the signature of an invisible runaway: report it even though no digest/SigNoz view shows it (session evidence: an 8-day `COUNT(*)` stuck in `Statistics` showed ~0 waits while its timer advanced 711,058 → 711,154s).
- Meaningful wait time (I/O, locks, mutex) = blocked → different category (lock contention / I/O bound).

### 0.3 Repetition / burst detection

A single snapshot misses bursty load. Take 2–3 snapshots ~10–60s apart:

- Same query shape present **every snapshot with fresh connection IDs and TIME≈0–2s** = a continuous storm or per-request fan-out (e.g. one pricing request opening 8–10 parallel queries across 9+ connections). Count concurrent copies per snapshot.
- Global rates — sample twice and divide by elapsed seconds:
    ```sql
    SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Threads_running','Threads_connected','Threads_created');
    ```
- **Cumulative digest counters mislead**: `events_statements_summary_by_digest.COUNT_STAR` accumulates over server uptime (often 40+ days). 67k executions over 43 days ≈ 1/min — not a storm. Sample `COUNT_STAR` twice ~30s apart: **identical counts = not the current load**; only deltas count.

### 0.4 Cumulative cost per query shape (multi-minute offenders)

```sql
SELECT SCHEMA_NAME, LEFT(DIGEST_TEXT,100) AS digest, COUNT_STAR,
       ROUND(SUM_TIMER_WAIT/1e12,1) AS total_sec, ROUND(AVG_TIMER_WAIT/1e12,1) AS avg_sec,
       ROUND(SUM_ROWS_EXAMINED/1e6,1) AS rows_exam_m, SUM_NO_INDEX_USED AS no_idx,
       FIRST_SEEN, LAST_SEEN
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME IS NOT NULL
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;
```

- `SUM_NO_INDEX_USED = COUNT_STAR` → every run full-scanned (missing index / non-sargable predicate).
- Large `avg_sec` (seconds–minutes) with small `COUNT_STAR` = the multi-minute scan family — e.g. a bare `COUNT(*)` over a 479M-row/29GB table ≈ 17 min/run. Sanity-check table size with `information_schema.TABLES.TABLE_ROWS` / `DATA_LENGTH`.
- The same themed scan (`SELECT COUNT(*) AS count FROM <table> LIMIT ?`) repeated across ~10 tables at a fixed cadence = one scheduled pipeline job — attribute the job, don't fix table-by-table.
- Non-sargable markers in the text: `FIND_IN_SET(`, `DATE_FORMAT(`, `DATE(`, `LIKE '%`, `ST_WITHIN`.

### 0.5 Feed findings forward

Every issue found here is a finding like any other: attach the per-query metrics from §1, classify it in §5, and carry it into the report/backlog of §6. A live, still-running thread gets an extra line: thread ID + owner (`USER`/`HOST`) + how long it has run, flagged **"kill candidate — needs a write connection"** (this connection is read-only).

## 1. Per-query metrics (required for every problematic query)

For **every query** you report as a finding — whether from ranking by total time, by latency, by frequency, an N+1, or an app anti-pattern — you MUST report three numbers:

- **Executions per day** — `signoz_aggregate_traces` aggregation `count` for the exact query text over `timeRange = 24h`. If the trace store is sampled, state that the count is the sampled-store count and, when possible, cross-check server-side (e.g. `mysql_global_status_*` counters, or a longer window) and say which figure you are reporting.
- **Median duration (p50)** — aggregation `p50`, `aggregateOn = durationNano`, same filter.
- **p95 duration** — aggregation `p95`, `aggregateOn = durationNano`, same filter.

Report them inline per finding, e.g. `~85×/day · median 4.2 ms · p95 18.0 ms`. Where a query cannot be captured in the trace store (scheduled jobs, sampled-out, writes not instrumented), say so explicitly and give the best available estimate with its source — do not silently omit the metrics.

## 2. Establish the load profile

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

## 3. Rank queries

- **By total DB time (CPU)**: `signoz_aggregate_traces` aggregation `sum`, `aggregateOn = durationNano`, `groupBy = service.name, db.query.text`, filter `db.query.text != '' AND deployment.environment = 'production'`, `timeRange = 24h`, `limit = 60`, order `sum(durationNano) desc`.
- **By latency (slow queries)**: aggregation `avg`, `aggregateOn = durationNano`, same groupBy/filter, order `avg(durationNano) desc`. Also `p99` for tail latency.
- **By frequency (N+1)**: aggregation `count`, same groupBy/filter, order `count() desc`.

For every query that lands in the report, add the per-query metrics from section 1: **count/day, p50, p95** (`signoz_aggregate_traces` aggregation `count` / `p50` / `p95`, `aggregateOn = durationNano`, same filter). Trace stores are usually sampled — a `count` from `signoz_aggregate_traces` is the sampled figure. When a query's volume looks anomalously low versus a prior report or the load profile (e.g. a job query that used to run ~7.8k/day now showing ~85/day), verify before reporting: widen the window (7d), check whether the statement text changed (a query rewrite changes `db.query.text` and orphans the old group), and check whether the workload that runs it (scheduled job, endpoint) actually executed in the window. State the reconciled figure and the cause of the delta in the finding.

## 4. Detect N+1

- Same point-lookup text executed ~1M+ times/day (`select * from X where id = ? limit 1`, `where <fk> = ?`).
- `count` grouped by `traceID, db.query.text` — same query text repeated >3× within a single trace.
- `count` grouped by `traceID` — traces with >10 DB spans.

For each N+1 query confirmed, report the per-query metrics from section 1 (count/day, p50, p95) and the per-trace repetition count.

## 4b. Detect application-level anti-patterns (inspect `db.query.text`)

Aggregate `count` grouped by `db.query.text` with these filters, and flag the offenders:

- **Over-fetching** — `db.query.text LIKE 'select *%'` (fetches whole wide rows when a few columns would do).
- **Existence/count check** — `db.query.text CONTAINS 'count(*)'` (a `COUNT(*)` that could be `EXISTS` / `limit 1` / cached).
- **Redundant ORM predicate** — `db.query.text CONTAINS ' is not null'` or `db.query.text CONTAINS ' in (?)'` with a single value (Eloquent's `whereNotNull`/single-element `whereIn` output).
- **Non-sargable predicate** — `db.query.text CONTAINS 'DATE('` / `'DATE_FORMAT('` / `'FIND_IN_SET('` / `"LIKE '%"` (function on a column defeats the index).
- **Connection churn** — `db.query.text LIKE 'SET %'` or `db.query.text LIKE 'use %'` (per-connection session setup = no pooling).
- **Single-row write** — `db.query.text LIKE 'insert into % values (?)'` (single-row inserts in a loop → bulk INSERT).
- **Missing cache** — a static reference lookup (countries/currencies/airports/settings) re-run ~1M+×/day.

## 5. Classify each finding

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

## 6. Write backlogs + report

- For each application with query-related findings, create a backlog file in `.agents/memory/work/active/` under that application's repo (e.g. `~/Development/Get-e/core`, `~/Development/Get-e/hotels-api`), one per application, all in parallel. The user will deliver each backlog to the owning project.
- Hardware / resource / lock / replication findings do not belong to an app repo — list them in a separate section of the report instead.
- Print a **global simplified report directly to the user**: a summary table grouped by category, each row = app · query (or signal) · category · **count/day · median · p95** · evidence · one-line fix.

Every query finding in both the backlog and the report MUST carry the three per-query metrics from section 1 — count/day, median (p50), and p95 duration — next to the query text. If a metric could not be obtained (sampling, no instrumentation), say so in the finding rather than omitting it.
