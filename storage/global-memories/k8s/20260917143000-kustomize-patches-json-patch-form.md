---
date: 2026-09-17
keywords: ["k8s", "kustomize", "patches", "revisionHistoryLimit"]
trigger-on: ["kustomize-patches", "revisionhistorylimit"]
---

## A kustomize `patches:` entry whose body is a strategic-merge document needs a JSON-patch body

A `patches:` entry whose body is a strategic-merge document (`apiVersion:` / `kind:` / `spec:`) fails the build with `error: trouble configuring builtin PatchTransformer with config ... unable to parse SM or JSON patch from [patch: "..."]` — it is a hard failure, not a silently skipped patch. Supplying an explicit `target:` does **not** rescue it; adding `target: {kind: Deployment}` to the SM-style body still fails to parse. The working form is a JSON patch, which is also the style these kustomizations already use for their OTEL env injection:

```yaml
- patch: |-
    - op: add
      path: /spec/revisionHistoryLimit
      value: 2
  target:
    kind: Deployment
```

Verified with `kustomize build`: all 12 Deployments in the directory receive the field while Service, ServiceAccount, ConfigMap and HTTPRoute are left untouched. This is the trap that sank `k8s-gete-dev` PR #73 (`e277057`), reverted three minutes later by PR #74 (`6d3b92c`) as "Fix/error" with no stated reason — so when a patch-carrying kustomization is reverted unexplained, suspect the patch body form rather than the intent.
