---
date: 2026-09-11
keywords: ["signoz", "promql", "label-churn", "dashboard"]
trigger-on: ["signoz-promql-series-churn"]
---

## A resource-attribute value change splits a PromQL series across time

A bare PromQL selector keeps one series per distinct label set, and a label set can differ over *time* as well as concurrently. When the collector stopped stamping `cloud.availability_zone` (d1868bb), the same metric became `{az="eu-central-1c"}` for one span and `{az=""}` for the next — two series, each covering part of the window, both rendering under the same legend as separate lines. Aggregate by the stable labels to merge them: `avg by ("deployment.environment") (rate({...}[5m]))`. `avg` rather than `sum` because the label variants are the same measurement duplicated, so summing double-counts. To tell whether a panel's duplicates are concurrent or time-churned, group by every varying resource attribute (e.g. via `signoz_query_metrics` with a multi-label groupBy) and inspect the spans.
