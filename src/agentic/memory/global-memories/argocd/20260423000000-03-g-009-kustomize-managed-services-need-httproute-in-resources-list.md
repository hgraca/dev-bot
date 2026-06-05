---
date: 2026-04-23
keywords: ["argocd", "sync"]
---

## G-009: Kustomize-managed services need httproute in resources list

- **Problem**: Services using `kustomization.yaml` (like hotels-api) explicitly list resources. Adding a new `httproute.yaml` file to the directory is not enough — ArgoCD won't sync it unless it's in the `resources:` list.
  Always add `- httproute.yaml` to the `resources` list in `kustomization.yaml` when adding Gateway API routes to Kustomize-managed services.
