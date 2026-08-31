---
date: 2026-08-20
keywords: ["signoz", "create-dashboard", "mcp", "dashboard", "widget"]
---

## signoz_create_dashboard MCP requires promql/clickhouse_sql/thresholds/contextLinks on every widget

The `signoz_create_dashboard` MCP tool validates against a stricter widget schema than the v1 write-shape stored in `dashboards/*.json`. Repo files like `MySQL RED.json` (POSTed by `scripts/import-dashboard.sh` to `/api/v1/dashboards`) omit `promql`, `clickhouse_sql`, `thresholds`, and `contextLinks`, and import fine — but the MCP tool rejects widgets missing them. When generating a dashboard JSON that will be created via MCP, give every widget `query.promql: []`, `query.clickhouse_sql: []`, `thresholds: []`, and `contextLinks: {"linksData": []}`. Copying a v1 write-shape file verbatim into the MCP tool fails schema validation even though the same JSON imports cleanly over the v1 API.
