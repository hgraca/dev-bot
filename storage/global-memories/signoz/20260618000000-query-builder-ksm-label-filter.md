---
date: 2026-06-18
keywords: ["signoz", "dashboard", "query-builder", "ksm"]
---

## SigNoz query builder v5 can't filter by KSM label attributes

The SigNoz query builder v5 expression parser fails to resolve certain KSM Prometheus labels as filter keys (e.g. `deployment`, `reason` on `kube_pod_container_status_waiting`). The API and field-value lookup both confirm the attributes exist with data, but the dashboard expression parser rejects them with "key not found". Workarounds: (a) use metric variants that encode the label in the metric name (e.g. `kube_pod_container_status_waiting_reason` instead of `kube_pod_container_status_waiting`), (b) remove the filter and accept all label values, (c) use PromQL instead of query builder for those panels.
