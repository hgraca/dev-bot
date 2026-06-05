---
date: 2026-04-22
keywords: ["argocd", "sync"]
---

## G-005: Deployment → StatefulSet is not an in-place update

- **Problem**: Changing `kind: Deployment` to `kind: StatefulSet` in a manifest is a different resource type. `kubectl apply` will fail or leave orphan pods if the old Deployment still exists.
  Delete the existing Deployment before applying the new StatefulSet. In ArgoCD/GitOps, this may require a sync with prune enabled or manual deletion.
