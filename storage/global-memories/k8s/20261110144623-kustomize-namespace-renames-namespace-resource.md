---
date: 2026-11-10
keywords: ["k8s", "kustomize", "namespace", "namespace-transformer", "prune"]
trigger-on: ["kustomize-namespace-transformer"]
---

## `namespace:` in a kustomization renames the Namespace resource itself

A `namespace: argocd` line in `kustomization.yaml` does not just default the namespace of namespaced objects — the namespace transformer also rewrites the `metadata.name` of any `Namespace` resource in the kustomization to that value, and rewrites `metadata.namespace` of every object that does not declare one. Moving a directory whose contents include `Namespace/otel-collector` and objects explicitly namespaced to `otel-collector` under an overlay that sets `namespace: argocd` therefore renames the Namespace to `argocd`, and an ArgoCD sync prunes `otel-collector` — deleting the namespace and everything running inside it. The tell is a rendered `kind/name` list that disagrees with the live one by exactly one Namespace. Omit `namespace:` entirely when the manifests already carry their own namespaces, and always diff the rendered `kind/name` set against the live Application's `status.resources` before adopting a moved directory.
