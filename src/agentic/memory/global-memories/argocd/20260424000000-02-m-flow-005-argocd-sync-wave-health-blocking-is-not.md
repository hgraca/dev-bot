---
date: 2026-04-24
keywords: ["argocd", "sync-wave", "sync", "application"]
---

## M-FLOW-005: ArgoCD sync-wave health blocking is not the same as app health

`argocd.argoproj.io/ignore-healthcheck: "true"` on a CronJob did not unblock sync-wave progression. The HTTPRoute in wave 1 was still not applied.
The `ignore-healthcheck` annotation prevents a resource from affecting the APPLICATION's overall health status, but ArgoCD still checks per-wave health during sync operations. To unblock, move the blocked resource to the same wave as the unhealthy resource (wave 0). Resources in the same wave are all applied together regardless of individual health.
