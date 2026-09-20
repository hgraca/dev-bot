---
date: 2026-09-10
keywords: ["signoz", "formula", "builder", "promql", "series-matching"]
trigger-on: ["signoz-alert-formula", "signoz-builder-formula"]
---

## SigNoz builder formulas drop series that are missing from a query

A builder formula is matched element-wise on labels: if a series exists in query A but not query B, `A - B` produces no result for that series (it is dropped, not treated as `B = 0`). Verified: `count(kube_pod_container_info) - count(kube_pod_container_resource_limits)` returned only the pods present in B, silently omitting the hundreds of pods that only exist in A. To keep the A-only series, use PromQL with `or`: `(A - B) or A` returns A for series absent from B.
