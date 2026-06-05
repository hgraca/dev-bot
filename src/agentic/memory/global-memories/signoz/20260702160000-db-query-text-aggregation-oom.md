---
date: 2026-07-02
keywords: ["signoz", "memory", "db.query.text", "oom", "aggregation"]
trigger-on: ["signoz-oom", "signoz-dashboard-oom", "db.query.text-memory"]
---

## SigNoz `db.query.text` aggregation with real SQL strings causes OOM — use `name` field for count panels

When `db.query.text` contains full SQL strings (e.g., `select * from trip_points where trip_points.trip_id = ?...`), trace aggregations grouping by `db.query.text` + `traceID` explode memory usage. Each unique SQL string consumes orders of magnitude more memory than grouping by span `name` (short strings like `sql SELECT`). A service with 10M+ DB spans and 1.9M unique SQL texts caused OOMKill even at 2Gi. For N+1 detection panels that only need DB span counts per trace, use `name LIKE 'sql %'` filter + groupBy `traceID`. Reserve `db.query.text` for panels that actually need to display the SQL text (e.g., slowest/frequent queries tables). This is specific to PHP OTel stacks where span `name` is `sql SELECT`/`sql INSERT` etc. and `db.query.text` is set by `opentelemetry-auto-pdo` or `opentelemetry-auto-laravel` QueryWatcher.
