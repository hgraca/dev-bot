---
date: 2026-10-28
keywords: ["k8s", "eks", "nodegroup", "PodEvictionFailure", "force"]
aliases: ["force flag stalls on PDB", "node group update looks hung", "PodEvictionFailure retries"]
trigger-on: ["eks-nodegroup-upgrade", "pdb-single-replica"]
---

## EKS `--force` does not bypass a blocking PDB immediately

`aws eks update-nodegroup-version --force` is documented as ignoring PodDisruptionBudgets, but it does not do so at once: each node carrying a pod whose PDB has `disruptionsAllowed=0` stalls roughly five to ten minutes before the force retry clears it, and the roll advances only then. Measured on staging on 2026-10-27, where the same stall recurred on every node and made a 5-node roll take over an hour. The window looks like a hung update — pod counts on the node sit frozen and nothing reports anything — but it is the retry budget draining. Deleting the pod directly (`kubectl delete pod`, which skips the eviction API that PDBs guard) unblocks the drain instantly, and is the faster remedy when a roll must proceed; fixing the PDB to permit one disruption is the durable one.
