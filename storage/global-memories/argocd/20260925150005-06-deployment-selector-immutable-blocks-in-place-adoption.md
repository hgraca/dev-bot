---
date: 2026-09-25
keywords: ["argocd", "deployment", "adoption", "selector", "helm"]
trigger-on: ["adopt-existing-deployment-into-argocd", "deployment-selector-immutable", "helm-adopt"]
---

## `spec.selector` is immutable, so a Deployment can never be adopted in place by a chart with different labels

Bringing a hand-applied Deployment under ArgoCD (or a Helm chart) fails with `spec.selector: Invalid value …: field is immutable` whenever the chart's selector differs from the live object's — ArgoCD is willing to adopt by patching, so the error is not "resource not managed by ArgoCD", but no amount of `ServerSideApply`, conflict resolution or `Replace` can change an immutable field. The live selector is whatever the original manifest used (here `app: cluster-autoscaler`, from the upstream autodiscover example) while a chart uses its own template labels (`app.kubernetes.io/instance` plus `app.kubernetes.io/name`), and those will not match. The only route is delete-and-recreate, which is safe done deliberately and in this order: **back up the objects first**; **push the chart definition first**, so the rendered output is visible while the old object still exists and can be abandoned if it is wrong; then delete. Objects without immutable fields — ServiceAccount, ClusterRole, ClusterRoleBinding — adopt by patch and must _not_ be deleted, so target only the Deployment. Before deleting anything, confirm the names the chart will create (`helm template` with the same values, or `fullnameOverride`) or the recreate lands beside the orphan as a duplicate.
