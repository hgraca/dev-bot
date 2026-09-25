---
date: 2026-09-25
keywords: ["k8s", "replicaset", "deployment", "pod-cleanup", "terminated-pod"]
trigger-on: ["k8s-stale-pod", "delete-pod-replicaset"]
---

## Before deleting a stray pod, check its ReplicaSet's DESIRED/READY — the order decides the outcome

A Deployment can leave a terminal pod behind for months: a container exits, the ReplicaSet creates a replacement, and the finished pod is never garbage-collected. `kubectl get pods` then shows one `Running` and one `0/1 Completed` — and the tempting misreading is that the Completed one belongs to an older, superseded ReplicaSet. Check the hashes first: in the observed case both pods came from the **same, current** ReplicaSet, so there had been no rollout at all.

Never delete it before reading `kubectl get rs`: if the ReplicaSet reports `DESIRED 1 CURRENT 1 READY 1` (satisfied by the Running pod), the terminal pod is not counted as active and deleting it is a no-op for the workload — the deployment stays healthy and nothing is recreated. If the ReplicaSet is **short** of its desired count, the controller sees one fewer active pod after the delete and **creates a replacement**, so removing the stray pod ADDS a replica rather than removing one. A terminated pod is cosmetic either way (the deployment reports available), so the safe move is: confirm the ReplicaSet is satisfied, then delete.
