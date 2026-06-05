---
date: 2026-05-01
keywords: ["signoz", "helm"]
---

## StatefulSet resources don't update on helm upgrade if release is in 'failed' state

If a helm install/upgrade enters `failed` state (e.g. --wait timeout), subsequent upgrades may not reconcile StatefulSet pod specs. The StatefulSet spec shows new values but pods keep old limits until manually deleted or the release is uninstalled and reinstalled cleanly.
Fix: `helm uninstall` + clean PVCs + fresh `helm install`. For ZooKeeper StatefulSets specifically, also delete the pod (`kubectl delete pod <name>`) after a successful upgrade to pick up new resource limits.
