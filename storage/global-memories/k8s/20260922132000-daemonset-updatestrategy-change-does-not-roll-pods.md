---
date: 2026-09-22
keywords: ["k8s", "daemonset", "updatestrategy", "rollout", "maxunavailable"]
trigger-on: ["daemonset-rollout", "updatestrategy-change", "rolling-update-tuning"]
---

## Changing a DaemonSet's `updateStrategy` rolls nothing — and `maxUnavailable` counts nodes, not pods

`updateStrategy` (like `minReadySeconds`) is not part of the pod template, so a change to it is recorded by the DaemonSet controller and **no pod is restarted**; it governs only the *next* rollout triggered by a genuine template or ConfigMap-checksum change. Two practical consequences: such a change is a zero-downtime way to soften a future roll (it produces no failure window of its own, so a push containing only that change will show no new pods and no incident — expected, not a failed sync), and verifying it requires reading the DaemonSet spec (`kubectl get ds -o jsonpath='{.spec.updateStrategy}'`, or ArgoCD reporting the resource as `configured`), because there is no pod-churn evidence to observe. The value also scales with `nodes`, not replicas: `rollingUpdate.maxUnavailable: 4` on a 9-node cluster replaces the endpoints on ~44% of nodes simultaneously, so any client holding a long-lived gRPC channel to a *Service* in front of those pods has ~44% of its connections severed at once. Lowering it to 2 halves the concurrent blast radius while leaving the total number of replaced endpoints per roll unchanged — the roll just takes proportionally longer in waves.
