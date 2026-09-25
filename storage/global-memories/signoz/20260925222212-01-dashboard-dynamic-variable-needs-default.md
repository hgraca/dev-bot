---
date: 2026-09-25
keywords: ["signoz", "dashboard", "variable", "defaultValue"]
trigger-on: ["signoz-dashboard-variable"]
---

## A SigNoz dynamic dashboard variable with no default renders every panel empty

A `ListVariable` backed by `signoz/DynamicVariable` (for example one bound to `deployment.environment`) needs an explicit `spec.defaultValue`. Without one the variable resolves to nothing on load, so every panel filter of the form `deployment.environment = $env` matches no series and the entire dashboard reads as "no data" — while the metrics are in fact arriving normally. The symptom is indistinguishable from an ingestion or query failure, which sends you looking in the wrong layer entirely; confirm the data is fine with a direct query first. Fix: set `defaultValue`, and match the working dashboards' `allowAllValue` / `allowMultiple`, then hard-refresh the browser. Vendor-curated dashboard templates are a common source of this omission — copy the shape from a dashboard known to work in the same instance instead.
