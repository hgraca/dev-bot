---
date: 2026-05-07
keywords: ["signoz", "helm", "chart"]
---

## SigNoz chart: disable dynamic provisioning with `global.storageClass: "-"` (NOT empty string)

To make all SigNoz chart PVCs (including the Altinity CHI operator's `volumeClaimTemplate` for ClickHouse) bind to pre-applied static PVs, set `global.storageClass: "-"`. The literal hyphen is the k8s convention for "no storage class". Empty string (`""`) does NOT disable dynamic provisioning — it falls back to the cluster default StorageClass (k3s `local-path`), and PVCs get bound to dynamically provisioned dirs instead of your static `claimRef` PVs.
Fix: `global.storageClass: "-"` in `signoz-values.yaml`. Verify with `kubectl get pvc -n observability -o yaml | grep storageClassName` — should show `""` (k8s normalizes `-` to empty in PVC spec while keeping the chart's request explicit).
