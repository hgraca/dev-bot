---
date: 2026-04-29
keywords: ["argocd", "sync"]
---

## M-ANTI-001: Do not remove Istio manifests before cleaning up cluster resources

Removing VirtualService YAML files from git caused ArgoCD to prune them, but the Istio webhook blocked the deletion. The cluster and git got out of sync with no way to reconcile without manual intervention.
Clean up in-cluster Istio resources (webhook, finalizers, CRs) BEFORE or AT THE SAME TIME as removing them from git. Never leave ArgoCD to prune Istio CRs while the Istio webhook is still active.

## See also

- [[key_decisions]]
- [[patterns]]
- [[gotchas]]
