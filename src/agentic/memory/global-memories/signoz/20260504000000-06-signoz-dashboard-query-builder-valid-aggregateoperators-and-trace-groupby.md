---
date: 2026-05-04
keywords: ["signoz"]
---

## SigNoz dashboard query builder: valid aggregateOperators and trace groupBy

- Valid space aggregations for metrics: `sum`, `avg`, `min`, `max`, `count`, `p50`, `p75`, `p90`, `p95`, `p99`. `latest` is NOT valid.
- For traces, the span operation name is a top-level column called `name`, not a tag called `operation`. GroupBy must use `{"key": "name", "dataType": "string", "type": "tag", "isColumn": true}`.
  Fix: Use `avg` for gauge metrics; use `name` with `isColumn: true` for trace operation grouping.
