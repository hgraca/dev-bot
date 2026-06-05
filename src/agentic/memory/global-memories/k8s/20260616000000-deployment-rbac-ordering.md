---
date: 2026-06-16
keywords: ["k8s", "deployment", "serviceaccount", "rbac"]
---

## K8s Deployment rollout timeout when referencing new ServiceAccount without RBAC applied first

When adding `serviceAccountName` to a Deployment that previously used the default SA, the new SA + ClusterRole + ClusterRoleBinding must exist in the cluster BEFORE the deployment pod starts. If the deploy target (Makefile, script, ArgoCD) applies the deployment manifest before the RBAC manifest, the pod fails with `CreateContainerConfigError` or stays in `Pending`, and `kubectl rollout status` times out. The fix: ensure RBAC manifests are applied before the deployment in all deploy targets. This is especially easy to miss when the RBAC YAML is a new file added alongside existing manifests — existing deploy scripts may not include it.
