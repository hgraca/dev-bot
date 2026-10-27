---
date: 2026-10-27
keywords: ["argocd", "kustomize", "directory source", "sync tasks", "kustomization"]
trigger-on: ["argocd-source-type", "gitops-digest-pin"]
---

## An explicit `spec.source.directory` block stops ArgoCD using kustomize

ArgoCD picks Kustomize only when the Application's source type is unset and the path contains a
`kustomization.yaml`. An Application created with `spec.source.directory: {recurse: true}` keeps
rendering that path in directory mode even after a kustomization is added — every YAML file in the
tree is treated as a resource, so `kustomization.yaml` (kind `Kustomization`, no CRD) and any
patch fragments fail validation and the sync reports "one or more synchronization tasks are not
valid (retried N times)" with nothing applied. Symptom that identifies it: digests in the manifests
were maintained by hand because the pin step had no kustomize target. Fix by removing the
`directory` key (`kubectl -n argocd patch application <app> --type=json -p '[{"op":"remove","path":"/spec/source/directory"}]'`)
or, better, change wherever the Application is declared — in-cluster-only definitions get reverted on
the next reconcile.
