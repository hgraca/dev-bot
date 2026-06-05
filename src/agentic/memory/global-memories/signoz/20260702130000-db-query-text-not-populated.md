---
date: 2026-07-02
keywords: ["signoz", "otel", "php", "db.query.text", "span-name"]
trigger-on: ["sigNoz-db-dashboard", "signoz-sql-filter", "db.query.text"]
---

## PHP OTel auto-instrumentation does NOT populate `db.query.text` — use span `name` instead

When building SigNoz dashboards for SQL performance (latency, frequency, N+1 detection), the `db.query.text` attribute is never populated by PHP OpenTelemetry auto-instrumentation. All spans have `db.query.text = ""`, `db.statement = ""`, `db.operation = ""`, `db.system = ""`. Instead, SQL spans are identified by their span `name` attribute: `sql SELECT`, `sql INSERT`, `sql UPDATE`, `sql DELETE`, and `sql` (generic). Dashboard widgets must filter on `name LIKE 'sql %'` rather than `db.query.text != ''`, and table widgets must `groupBy` on `name` instead of `db.query.text`. The `selectedTracesFields` must also reference `name` (core field: `id: "name--string--core--true"`).
