---
date: 2026-11-15
keywords: ["k8s", "kubectl", "apply", "last-applied-configuration"]
aliases: ["duplicate volume name", "apply deletes both entries", "ValidationError volumeMounts Not found"]
trigger-on: ["kubectl-apply-list-merge", "duplicate-list-item"]
---

## A duplicated list item in `last-applied-configuration` breaks every later `kubectl apply`

When a manifest declares the same `volumes` entry (or any list keyed by name) twice and is applied, the duplicate lands in the `kubectl.kubernetes.io/last-applied-configuration` annotation. Fixing the file does not fix the cluster: the three-way merge keys lists by name, so removing one of two identical entries makes kubectl delete **both**, and the apply fails with `volumeMounts[0].name: Not found: "<name>"`. `--dry-run=server` reproduces it; `kubectl replace -f` succeeds but leaves the bad annotation, so the next `apply` fails again. Repair: `kubectl annotate deploy/<name> kubectl.kubernetes.io/last-applied-configuration-` to drop the corrupted annotation, then `kubectl apply -f` (kubectl rebuilds it from the file). Verify with `kubectl diff -f` printing nothing, and check the live object's list matches the file.
