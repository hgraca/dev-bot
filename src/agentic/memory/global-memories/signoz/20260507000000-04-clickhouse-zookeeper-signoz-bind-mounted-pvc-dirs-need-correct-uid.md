---
date: 2026-05-07
keywords: ["signoz", "helm", "chart"]
---

## ClickHouse + Zookeeper + signoz bind-mounted PVC dirs need correct UID ownership (per-subdir matrix)

Date: 2026-05-07 (updated from 2026-05-06 entry — Task 4 static-PV mechanism)
Symptom: ClickHouse / Zookeeper / signoz pod stuck in `CrashLoopBackOff` with `Permission denied` on `/var/lib/clickhouse/` (or equivalent).
Cause: Host-side per-subdir owner doesn't match the container's `runAsUser`. `fsGroup` is unreliable for `local` PVs in k3s (does not run the chmod helper for `local` volume type).
Fix (matches Task 4 static-PV layout — verified via helm template signoz/signoz --version 0.121.0):

```
sudo chown -R 101:101    ./storage/signoz/clickhouse      # ClickHouse (Altinity-CHI runAsUser: 101)
sudo chown -R 1001:1001  ./storage/signoz/zookeeper       # Bitnami ZK runAsUser: 1001
sudo chown -R 0:0        ./storage/signoz/signoz-sqlite   # signoz binary: no USER in image → root (UID 0)
sudo chmod 0700 ./storage/signoz/{clickhouse,zookeeper,signoz-sqlite}
```

This is automated by `make _ensure-signoz-storage-dirs` (calls `scripts/storage/chown-if-needed.sh`).
Re-verify on every chart bump via: `helm template signoz/signoz --version <ver> | grep -A5 securityContext`
