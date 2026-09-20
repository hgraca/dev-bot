---
date: 2026-09-15
keywords: ["signoz", "error-rate", "traces", "p99", "deployment"]
trigger-on: ["signoz-health-check", "signoz-error-rate", "deploy-verification"]
---

## SigNoz's per-service error rate reflects entry-point spans only, and one service name can span environments

The service list / per-service `errorRate` is computed from an application's inbound entry-point spans, so it can report a clean 0 while the same service emits a steady stream of *outbound* client spans marked `has_error` (e.g. an external API answering 422). Treat the service metric as "inbound health", not "all errors", and always follow up with an explicit error-span query grouped by `name` / `http.response.status_code` / `url.path` when verifying a deploy — otherwise a real error pattern stays invisible. Also: when the same chart is deployed to several environments, a single `service.name` covers them all, so unfiltered queries mix prod and staging — scope with `k8s.cluster.name` (or `deployment.environment`) first, and remember telemetry lags real time, so a just-finished rollout yields only minutes of data. Finally, percentiles are not comparable across window lengths: a 5-minute p99 and a 6-hour composite p99 describe different populations, so a dramatic "regression" can be pure artefact. Judge a deploy by comparing same-length windows either side of the event, and group by operation to see which one actually carries the tail.
