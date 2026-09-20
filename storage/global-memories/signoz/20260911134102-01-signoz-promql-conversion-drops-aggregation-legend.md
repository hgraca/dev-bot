---
date: 2026-09-11
keywords: ["signoz", "promql", "dashboard", "legend"]
trigger-on: ["signoz-dashboard-promql-panel"]
---

## Converting a SigNoz Query Builder panel to PromQL drops aggregation — name the label in the legend

A Query Builder metrics panel aggregates across series (e.g. `spaceAggregation: sum` with `groupBy: deployment.environment`), so a metric carrying extra labels collapses to one line per group. Replacing it with a bare PromQL selector such as `rate({"mysql_global_status_commands_total", "deployment.environment"=~"$env"}[5m])` keeps every distinct label set as its own series. If the legend only interpolates a constant label (`{{deployment.environment}} commands/sec`), all of them render with identical names — here one line per MySQL `command` value (100+), and the same for `mysql_global_status_connection_errors_total`'s `error` label. Fix by either aggregating in the expression (`sum by ("deployment.environment") (rate(...))`) or adding the distinguishing label to the legend (`{{deployment.environment}} {{command}} commands/sec`). Before using `rate()`, also confirm the metric type: mysqld-exporter exposes some status counters (e.g. `mysql_global_status_threads_created`) as **gauges**, where `rate()` is not meaningful.
