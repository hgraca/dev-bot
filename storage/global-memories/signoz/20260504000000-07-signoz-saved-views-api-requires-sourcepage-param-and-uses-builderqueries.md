---
date: 2026-05-04
keywords: ["signoz"]
---

## SigNoz saved views API: requires sourcePage param and uses builderQueries map

- POST `/api/v1/explorer/views` with `{name, sourcePage:"logs", tags:[], compositeQuery:{queryType:"builder", panelType:"list", builderQueries:{"A":{...}}}}`
- `compositeQuery` uses `builderQueries` (a **map** keyed by query name), NOT `builder.queryData` (array) like dashboards use.
- `panelType` and `queryType` are required inside `compositeQuery`.
- For logs list view: `aggregateOperator: "noop"`, `dataSource: "logs"`.
- Filter on `service.name` uses `type: "resource"` (not `"tag"`).
- GET list requires `?sourcePage=logs` query param — without it returns `data: null`.
  Fix: See log-views/*.json for working format. [[memories]]
