---
date: 2026-09-25
keywords: ["k8s", "pod-anti-affinity", "scheduling", "topology", "ebs"]
trigger-on: ["pod-anti-affinity", "spread-workloads-across-nodes", "statefulset-placement"]
---

## Pod anti-affinity is evaluated only for the pod being scheduled — write it on both sides

A required `podAntiAffinity` rule of the form "do not schedule X where Y runs" stops _X_ landing on Y's node, but does nothing to prevent **Y** being scheduled onto X's node, because the scheduler evaluates only the incoming pod's rules against the labels of pods already placed. A one-sided rule therefore appears to work — X visibly moves off the shared node — while quietly losing its guarantee the moment the unconstrained half is rescheduled, and a later reader sees an anti-affinity rule and assumes separation is enforced. Whenever the invariant is "these two must never co-locate", write the mirror rule on both workloads, or give them a shared label so a single selector covers the pair. One practical constraint for stateful workloads: an EBS-backed PVC is availability-zone-bound through its PV's `nodeAffinity`, so a hard anti-affinity rule can only be satisfied by a node in the **volume's** AZ — count the candidate nodes in that AZ before adding the rule (a different-AZ sibling is not a candidate at all), or the moved pod goes `Pending` instead of relocating, which for a database is an outage rather than a scheduling delay.
