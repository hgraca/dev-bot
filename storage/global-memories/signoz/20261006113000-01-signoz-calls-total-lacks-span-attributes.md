---
date: 2026-10-06
keywords: ["signoz", "signoz_calls_total", "spanmetrics", "dashboard", "span-attributes"]
aliases: ["calls_total", "spanmetrics dimensions", "request rate panel"]
trigger-on: ["signoz-dashboard-metric", "signozspanmetrics"]
---

## `signoz_calls_total` carries no span attributes — classify panels over the traces table

SigNoz's generated `signoz_calls_total` metric is produced by the `signozspanmetrics/delta`
processor and carries only `service.name`, `operation`, `span.kind`, `status.code`,
`deployment.environment`, `service.namespace` and `signoz.collector.id`. The processor's
`dimensions` block adds resource and collector attributes but never span attributes, so a panel
built on this metric cannot separate outbound HTTP (`http.request.method`) from DB/Redis calls
(`db.system`), cannot filter by `http.route`, and cannot tell a CLI-command span from an HTTP
request. A panel that sums it grouped only by `service.name` is a span-throughput chart, not a
request rate — in one production hour `Server` (real inbound HTTP) was ~1% of the total.

To split traffic by span attribute, build the panel as a ClickHouseSQL (or traces-signal) query
over `signoz_traces.distributed_signoz_index_v3`, where those attributes live. Span kind is the
numeric `kind` column: 1 Internal, 2 Server, 3 Client, 4 Producer, 5 Consumer. Use `kind` for
direction (Server = inbound HTTP, Client = outbound) and `attributes_string['db.system']` /
`mapContains(attributes_string,'http.request.method')` for the HTTP-vs-datastore split.
