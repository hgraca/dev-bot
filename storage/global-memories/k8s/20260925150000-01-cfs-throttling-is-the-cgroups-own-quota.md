---
date: 2026-09-25
keywords: ["k8s", "cfs-throttling", "cadvisor", "cpu-limits", "psi"]
trigger-on: ["kubernetes-cpu-limits", "container-cpu-throttling", "cadvisor-metrics"]
---

## CFS throttling is caused by a cgroup's own quota, and cadvisor only exposes it for cgroups that set a limit

`container_cpu_cfs_throttled_periods_total` counts the periods in which a cgroup exhausted **its own** `cpu.max` quota, so a throttled container is simply one demanding more than its own limit — neighbour contention cannot increment it, and moving a co-tenant off the node will not relieve it. That gives a second, easily-missed diagnostic: cadvisor emits **no** `container_cpu_cfs_*` series at all for a cgroup without a CPU limit, so an entire node reporting zero of them means "no container here sets a CPU limit", not "nothing is throttled" — observed on a ten-node EKS cluster where the only node publishing those series was also the only node whose pods (`mongodb`, `opensearch`) declared limits. When the quota counters are absent, the always-available contention signal from the same endpoint is PSI (`container_pressure_cpu_waiting_seconds_total` and `..._stalled_...`), available per-pod and per-container as well as for `id="/"` — though for the root cgroup the `some`-style `waiting` value accumulates readily and is a weaker signal than `stalled`. Always derive a **rate** from two reads rather than quoting the cumulative value: a pod-scope counter survives container restarts while the container-scope counter resets, which is how a pod showing 119 restarts read 5,988 s throttled at pod scope against 12.9 s at container scope.
