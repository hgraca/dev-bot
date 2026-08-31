---
date: 2026-07-02
keywords: ['signoz', 'traces', 'aggregation']
---

## signoz_execute_builder_query does not support aggregate/scalar requestType for traces

When using `signoz_execute_builder_query` for traces, the only valid `requestType` values are `"time_series"` and `"raw"`. Using `"aggregate"` or `"scalar"` returns: `unsupported requestType 'aggregate' for traces`.

For trace aggregations (avg, count, p95, p99, groupBy), use `signoz_aggregate_traces` instead. It accepts `aggregation`, `aggregateOn`, `groupBy`, `filter`, `orderBy`, `limit`, `requestType` (scalar or time_series), and `timeRange` parameters directly — no compositeQuery wrapper needed.

Correct: `signoz_aggregate_traces(aggregation="avg", aggregateOn="durationNano", groupBy="db.query.text", filter="service.name = 'transfers'", timeRange="30m", requestType="scalar")`
