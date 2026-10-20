---
date: 2026-10-15
keywords: ["signoz", "metrics", "builder-query", "empty-panel"]
aliases: ["metric not found", "has never been received", "panel ahead of instrumentation"]
---

## A SigNoz query for a never-received metric succeeds with empty rows, not an error

Authoring a panel or alert for a metric before any service emits it is safe.
`signoz_execute_builder_query` on an unknown metric returns `status: success` with empty results
and a **non-fatal** warning — `metric <name> has never been received. Check the metric name and
instrumentation` — so the panel renders empty rather than erroring. A dashboard can therefore be
built ahead of the instrumentation that will feed it.

The same call is a cheap structural test: attribute filters (`monitor.status IN ('ok','error')`)
and attribute group-bys (`fieldContext: attribute`) resolve even when the named metric does not
exist yet, so the query shape can be proven against a *different*, live metric before the real
data lands.
