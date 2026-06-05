---
date: 2026-08-07
keywords: ["signoz", "n+1", "eloquent", "performance", "otel"]
trigger-on: ["signoz-n1-detection", "eloquent-n1-detection", "sql-select-count-per-trace"]
---

## Detect N+1 queries by counting sql SELECT spans per trace

Use `signoz_aggregate_traces` with `filter: "service.name = '<svc>' AND name = 'sql SELECT'"`, `groupBy: "traceID"`, `aggregation: count`, and `orderBy: "count() desc"` to find traces with disproportionately high SQL counts. A trace with hundreds or thousands of `sql SELECT` spans indicates N+1 lazy-loading. Then drill into the top trace with `signoz_aggregate_traces` grouping by `name` (e.g. `Contract::get`, `Hotel::find`) to identify which models trigger the repeated queries. Use `signoz_get_trace_details` to see the root span's `http.route` or pod name (for Kafka consumers) to map to the handler. A 30-minute window is sufficient for active services.
