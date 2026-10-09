---
date: 2026-10-06
keywords: ["signoz", "clickhouse", "dashboard", "panel", "query"]
aliases: ["clickhouse_sql panel", "dashboard variable substitution"]
trigger-on: ["signoz-clickhouse-panel"]
---

## SigNoz ClickHouseSQL panel queries are executed verbatim, with variables pre-substituted

A ClickHouseSQL dashboard panel's `query` string is sent to ClickHouse exactly as stored —
SigNoz wraps nothing and appends no `SETTINGS`, so a trailing `SETTINGS log_comment = '...'`
survives and any hand-written clause is preserved (verified by reading `system.query_log` for a
live panel). Dashboard variables are substituted before the query reaches ClickHouse:
`$environment` → `'production'`; `$start_datetime`/`$end_datetime` → `toDateTime(<epoch-seconds>)`;
`$start_timestamp`/`$end_timestamp` → bare epoch seconds; and the multi-select `$service` → a
parenthesised list `(['a','b',…])`, so `col IN ($service)` is correct. Put the `ts_bucket_start
BETWEEN $start_timestamp - 1800 AND $end_timestamp` guard alongside the `timestamp` filter.

A timeseries panel (`"kind":"time_series"`) must return `ts` (the bucket) and `value`, with any
other column acting as the series label — e.g. `concat(serviceName,' in') AS service` yields one
series per concatenated label, which is how to draw two series (in/out) from a single query. A
table panel (`"kind":"scalar"`) returns labelled columns. `serviceName` is a real column and
`resources_string['deployment.environment']` works for the environment filter.
