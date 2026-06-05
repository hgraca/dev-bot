---
date: 2026-06-17
keywords: ["signoz", "mcp", "dashboard", "api"]
---

## SigNoz GET dashboard endpoint wraps payload in double data nesting

When calling `signoz_get_dashboard` (or `GET /api/v1/dashboards/<uuid>`), the response structure is `{data: {createdAt, updatedAt, id, data: {...dashboard...}, locked, org_id}}`. The actual dashboard payload (title, description, widgets, layout, variables, tags, version) is at `.data.data` — two levels of `data` nesting. To extract the import-compatible dashboard JSON, use `jq '.data.data'`. Failing to strip the outer wrapper and saving the full response results in an invalid body for `POST /api/v1/dashboards` (import-dashboard.sh), which expects the inner dashboard object directly.
