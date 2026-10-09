---
date: 2026-10-05
keywords: ["signoz", "service.name", "groupBy", "fieldContext", "traces"]
trigger-on: ["signoz-dashboard-trace-groupby", "signoz-query-builder-groupby"]
aliases: ["service name empty series", "groupBy shows one metric", "resource vs attribute context"]
---

## SigNoz trace queries must group `service.name` with `fieldContext: "resource"`, not `"attribute"`

A dashboard `builder_query` with `signal: "traces"` that groups by `service.name` using `fieldContext: "attribute"` silently resolves the key to an empty string: the query returns a single series labelled `service.name = ""` instead of one per application, and a formula over those queries collapses to one line — the user-visible symptom is "the panel only shows one metric" with no error. `service.name` is a resource attribute, so the groupBy must be `{name: "service.name", signal: "", fieldContext: "resource", fieldDataType: ""}` (adding `signal: "traces"` also works). Metrics-signal queries tolerate either context, so the bug only surfaces on traces. Verify against the live instance with a raw `POST /api/v5/query_range`: the broken form returns `nSeries: 1` with an empty label value, the fixed form one series per service. That v5 payload accepts only `schemaVersion`, `start`, `end`, `requestType`, `compositeQuery`, `variables`, `noCache`, `formatOptions` — a top-level `step` is rejected with `unknown field "step"`.
