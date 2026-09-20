---
date: 2026-09-10
keywords: ["signoz", "log-alert", "growth", "clickhouse-sql", "previous-period"]
trigger-on: ["signoz-log-alert", "signoz-clickhouse-alert"]
---

## SigNoz log alerts have no previous-period comparison — growth needs a ClickHouse SQL query

SigNoz log-based alerts (query builder) share one time range across all queries and offer no window-shift/derivative, so "volume grew X% versus the previous minute" cannot be expressed in the builder — it needs a `clickhouse_sql` alert query. The working envelope is `condition.compositeQuery: { queryType: "clickhouse_sql", queries: [{ type: "clickhouse_sql", spec: { name, query, legend } }] }` (the SQL lives under `spec.query`); passing `compositeQuery.clickhouse_sql: [...]` (the dashboard-style array) to `execute_builder_query` is rejected with "missing or empty compositeQuery.queries". Log SQL uses `$start_timestamp`/`$end_timestamp` (seconds) and `$start_timestamp_nano`/`$end_timestamp_nano` (nanoseconds), and must filter `signoz_logs.distributed_logs_v2` by `resource_fingerprint GLOBAL IN (__resource_filter)` plus both `ts_bucket_start` and `timestamp`.
