---
date: 2026-05-04
keywords: ["signoz"]
---

## SigNoz 0.121.0 alert rules require v5 API format

The `/api/v2/rules` endpoint returns generic `validation failed` with no detail. Use `/api/v1/rules` instead — it returns specific field-level errors. The v5 format requires:

- `"alert"` field (not `"alertName"`)
- `"version": "v5"` mandatory
- `condition.compositeQuery.queries` is an array of `{type: "builder_query", spec: {...}}` envelopes (not a `builderQueries` map)
- `spec` uses `signal: "metrics"` (not `dataSource`), `name` (not `queryName`), and `aggregations` array with `{metricName, timeAggregation, spaceAggregation}`
- `compositeQuery` needs `panelType` and `queryType` fields
- A notification channel must exist before creating rules (threshold validation requires `preferredChannels` to reference an existing channel)
  Fix: See commit 249347b for the working format.
