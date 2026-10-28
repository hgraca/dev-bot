---
date: 2026-10-28
keywords: ["k8s", "statefulset", "maxUnavailable", "argocd", "dropDisabledFields"]
aliases: ["statefulset maxUnavailable ignored", "patch reports success field missing", "permanent OutOfSync statefulset"]
trigger-on: ["statefulset-updatestrategy", "argocd-outofsync"]
---

## A StatefulSet silently drops `maxUnavailable` unless the object already has it

Setting `spec.updateStrategy.rollingUpdate.maxUnavailable` on a StatefulSet can report success and store nothing: `kubectl patch` prints `patched`, ArgoCD syncs `Succeeded`, the live object still has no field — and `managedFields` records that write as the most recent one, so nothing reverted it; it was never persisted. Observed against EKS 1.35.8 in October 2026: three `OrderedReady` StatefulSets never acquired the field and stayed permanently `OutOfSync` against a manifest carrying it, while a fourth `OrderedReady` StatefulSet that already had the value kept it across writes (so "only honoured with `podManagementPolicy: Parallel`" is not the explanation). The pattern matches the API server's `dropDisabledFields` behaviour — a field belonging to a disabled capability is dropped unless the object is already using it. Consequence for GitOps: a manifest that specifies such a field can never converge, so omit it rather than fight the sync.
