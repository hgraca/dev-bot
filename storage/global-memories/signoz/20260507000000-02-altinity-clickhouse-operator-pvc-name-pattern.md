---
date: 2026-05-07
keywords: ["signoz", "helm", "chart"]
---

## Altinity ClickHouse-operator PVC name pattern

The CHI operator generates PVC names from the `volumeClaimTemplate.metadata.name` in the `ClickHouseInstallation` CR — NOT the StatefulSet name like Bitnami/upstream charts. For the SigNoz chart shipping CHI template `volumeclaim-template`, the actual PVC is `data-volumeclaim-template-chi-<release>-<cluster>-<shard>-<replica>-0`, not `data-chi-<release>-<cluster>-<shard>-<replica>-0` as one would guess from upstream-StatefulSet naming. Verify live after first `helm install` via `kubectl get pvc -n observability` before writing any `claimRef`.
Fix: Pre-flight `kubectl get pvc -n observability -o name` after first chart install; copy the exact name into the static-PV `claimRef.name`. See `k3d/manifests/storage/signoz-pvs.yaml`.
