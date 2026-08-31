---
date: 2026-06-18
keywords: ["argocd", "kustomize", "configMapGenerator", "disableNameSuffixHash"]
---

## Kustomize configMapGenerator needs unique names across apps in same namespace with ArgoCD

When multiple ArgoCD apps use kustomize's `configMapGenerator` with `disableNameSuffixHash: true` and deploy to the same namespace, the generated ConfigMap names must be unique. If two apps generate a ConfigMap with the same name (e.g. `otel-env`), ArgoCD sees a collision — the first app creates the resource, and subsequent apps report `OutOfSync` because they cannot overwrite it. The default kustomize behavior (`disableNameSuffixHash: false`) prevents this by appending a content hash, but when the suffix is explicitly disabled for stable names, uniqueness must be ensured by the name itself. Fix: prefix or suffix the ConfigMap name with a service-identifying token (e.g. `otel-env` → `otel-env-drivers`, `otel-env-hotels-api`), and update all patch/deployment references to match.
