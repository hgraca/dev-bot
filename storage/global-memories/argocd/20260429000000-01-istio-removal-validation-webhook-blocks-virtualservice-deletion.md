---
date: 2026-04-29
keywords: ["argocd", "sync"]
---

## Istio removal: Validation webhook blocks VirtualService deletion

The `istiod-istio-system` ValidatingWebhookConfiguration remains in the cluster even after istiod is stopped. It intercepts ALL mutations to Istio CRs (VirtualService, Gateway, etc.) and rejects them with "unrecognized type". This blocks `kubectl patch` to remove finalizers, which blocks deletion, which blocks ArgoCD sync — creating a deadlock.

Delete the webhook BEFORE removing Istio resources from manifests:

```bash
kubectl delete validatingwebhookconfiguration istiod-istio-system
```
