---
date: 2026-09-11
keywords: ["signoz", "clickhouse", "dashboard", "variables"]
trigger-on: ["signoz-dashboard-clickhouse-panel", "signoz-clickhouse-query"]
---

## SigNoz dashboard ClickHouse SQL panels: variables and metrics attribute access

SigNoz dashboard `clickhouse_sql` panels substitute `{{.name}}` variables server-side, and string variables are inserted **already quoted** — write `WHERE env = {{.environment}}`, never `= '{{.environment}}'` (the extra quotes produce `''production''` and a syntax error). The built-in `{{.start_timestamp_ms}}` / `{{.end_timestamp_ms}}` work in panels, so bucket size can adapt to the range with `toIntervalSecond(greatest(60, intDiv({{.end_timestamp_ms}} - {{.start_timestamp_ms}}, 1000 * 120)))`. For the metrics tables, resource attributes live in the `resource_attrs` Map — `resource_attrs['service.name']`, `resource_attrs['soft_limit.cpu']` — not in the `labels` JSON (empty for these OTel metrics); the `env` LowCardinality column equals `deployment.environment` and is the cheapest environment filter. Join `distributed_samples_v4` to `distributed_time_series_v4_1day` (DISTINCT fingerprint) for fingerprint→attribute lookups that stay valid across arbitrary time ranges. When driving a query through the MCP query API, `variables` must be shaped `{"name": {"value": "..."}}` — a plain string fails with a `VariableItem` decode error.
