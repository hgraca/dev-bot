---
date: 2026-04-29
keywords: ["argocd", "sync"]
---

## Istio removal: foregroundDeletion finalizer stalls ArgoCD

When ArgoCD prunes Istio VirtualServices, Kubernetes adds a `foregroundDeletion` finalizer. If istiod is gone, nothing processes the finalizer → the resource hangs forever → ArgoCD shows `OutOfSync` / `Progressing` indefinitely.

After removing the validation webhook, patch out finalizers:

```bash
kubectl patch virtualservice <name> -n <ns> --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```
