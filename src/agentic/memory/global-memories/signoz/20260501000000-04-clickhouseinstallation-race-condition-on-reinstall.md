---
date: 2026-05-01
keywords: ["signoz", "helm"]
---

## ClickHouseInstallation race condition on reinstall

If you `helm uninstall` and immediately reinstall, the clickhouse-operator may still be processing the delete of the old ClickHouseInstallation CRD. The new CRD created by helm install can be deleted by the operator's cleanup, leaving no ClickHouse pod. Symptoms: no `chi-*` pod appears, `kubectl get clickhouseinstallations` returns empty.
Fix: Wait for full cleanup (namespace delete + finalizer removal) before fresh install. Or re-apply the CHI manifest: `helm get manifest signoz -n observability | sed -n '<chi-lines>' | kubectl apply -f -`
