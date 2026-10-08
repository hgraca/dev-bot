---
date: 2026-10-07
keywords: ["signoz", "clickhouse", "filter", "expression", "sql"]
trigger-on: ["signoz-dashboard-sql", "signoz-alert-filter"]
---

## SigNoz filter-expression and ClickHouse literal gotchas

- **A ClickHouse SQL panel needs single-quoted string literals.** Double quotes are **identifiers**, so `formatDateTime(x, "%Y")` is an unknown-identifier error, not a string. It fails only at query time — the dashboard importer never runs the SQL, so a broken panel imports "successfully" and shows an error to the viewer.
- **`<attr> != ''` can match nothing.** In both the builder filter language and the log-search API, `service.version != ''` returned zero rows against data that plainly had values, while `service.version EXISTS` returned them. Prefer `EXISTS` over comparing to an empty string.
- **`toUnixTimestamp64Nano(now())` fails** — `now()` is `DateTime`, the function wants `DateTime64`. Compute nanos from seconds, e.g. `(toUnixTimestamp(now()) - 21600) * 1000000000`, or cast first.
- **The logs table is `signoz_logs.distributed_logs_v2`** with nanosecond `timestamp`. Filter resource attributes through the `distributed_logs_v2_resource` CTE (`simpleJSONExtractString(labels, 'service.name') = …`) and bound `ts_bucket_start BETWEEN $start_timestamp - 1800 AND $end_timestamp` alongside `timestamp BETWEEN $start_timestamp_nano AND $end_timestamp_nano`; `$start_timestamp` is in seconds, `$start_timestamp_nano` in nanoseconds.
- **A scalar ClickHouse panel returns whatever columns the SELECT produces** — it does not need a `ts` column, which is what makes a `service | time | digest` table panel possible.
