---
date: 2026-10-28
keywords: ["k8s", "pdb", "node drain", "disruptionsAllowed"]
aliases: ["minAvailable 50% blocks drain", "PodDisruptionBudget single replica", "disruptionsAllowed 0"]
trigger-on: ["pdb-single-replica", "node-group-upgrade"]
---

## `minAvailable: 50%` on a single-replica workload permanently blocks node drains

A percentage budget on a one-pod workload rounds up: 50% of 1 is 0.5, rounded up to 1, so `desiredHealthy` is 1 and `disruptionsAllowed` is `1 - 1 = 0` forever. The PDB then protects nothing — there is no second copy — while forbidding voluntary eviction, so every `kubectl drain` and every EKS managed node group update stalls on that pod and eventually fails with `PodEvictionFailure`. Measured on 2026-10-28 against production: nine PDBs in this shape, all `expectedPods=1, disruptionsAllowed=0`. Use `maxUnavailable: 1` for single-replica workloads — it says "one pod may go", and on a multi-replica workload it is equivalent to or stricter than `minAvailable: 50%`. Audit with `kubectl get pdb -o custom-columns='NAME:.metadata.name,EXPECTED:.status.expectedPods,ALLOWED:.status.disruptionsAllowed'`: rows with `expected=0` match nothing and are harmless; `expected>=1` with `allowed=0` will block.
