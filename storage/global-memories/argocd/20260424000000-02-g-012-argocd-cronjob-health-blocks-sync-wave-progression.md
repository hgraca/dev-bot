---
date: 2026-04-24
keywords: ["argocd", "sync-wave", "sync"]
---

## G-012: ArgoCD CronJob health blocks sync-wave progression

- **Problem**: A CronJob with failed last execution makes ArgoCD mark wave 0 as unhealthy, blocking progression to wave 1+. The `argocd.argoproj.io/ignore-healthcheck: "true"` annotation only affects the app-level health, NOT sync-wave progression.
  Move downstream resources (like HTTPRoute) to wave 0 so they're applied in the same batch as the failing CronJob. Keep `SkipDryRunOnMissingResource=true` for CRD-dependent resources.
