---
date: 2026-06-18
keywords: ["k8s", "crashloopbackoff", "kube-state-metrics", "kube_pod_container_status_waiting"]
---

## CrashLoopBackOff detection via kube_pod_container_status_waiting metric

Use `kube_pod_container_status_waiting` (KSM gauge metric) with filter `reason = 'CrashLoopBackOff'` to count pods stuck in crash loops. This metric exposes a `reason` label with values like CrashLoopBackOff, ErrImagePull, ImagePullBackOff, CreateContainerConfigError, etc. Sum aggregation gives the count of affected pods. Pair with `kube_pod_container_status_restarts_total` (rate) for full crash-loop visibility: the waiting metric shows current state, the restarts metric shows frequency over time.
