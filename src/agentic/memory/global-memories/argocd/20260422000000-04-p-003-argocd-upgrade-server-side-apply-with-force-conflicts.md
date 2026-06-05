---
date: 2026-04-22
keywords: ["argocd"]
---

## P-003: ArgoCD upgrade — server-side apply with force-conflicts

- **Pattern**: ArgoCD system upgrades use `kubectl apply -n argocd -f <manifest-url> --server-side --force-conflicts`. The `--server-side --force-conflicts` flags are required because CRDs and large manifests exceed annotation size limits.
- **When**: Upgrading ArgoCD on this cluster.
