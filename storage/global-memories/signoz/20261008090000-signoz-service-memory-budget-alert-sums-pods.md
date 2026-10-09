---
date: 2026-10-08
keywords: ["signoz", "memory", "alert", "kubernetes", "pod-name"]
aliases: ["memory budget alert", "service memory spike", "container.memory.working_set"]
---

## A service-level memory budget alert sums all pods — localize by k8s.pod.name

A "high memory" alert scoped to `service.name` typically sums `container.memory.working_set` across
every pod of the service (spaceAggregation `sum`) and compares that total to a per-service budget
label. One pod can therefore move the whole service line — e.g. 50% → 80% of budget — so the way to
find the cause is to re-run the same metric broken down by `k8s.pod.name` over a before/after window
(scalar queries), identify the single pod that moved, then read that pod's logs/traces for the job
that ran at the step. Two related traps: when pods have no `resources.limits`, the
`k8s.container.memory_limit_utilization` / `k8s.pod.memory_limit_utilization` metrics emit nothing at
all (the metric is skipped if any container lacks a limit), so a ratio-to-limit panel is empty and a
budget label is the only yardstick; and PHP CLI processes do not return freed heap to the OS, so a
finished job's peak RSS stays resident until the process is recycled by the worker's `--memory`
threshold. Concrete SigNoz instance: `observability/src/alerts/budget-memory-*.json` — metric
`container.memory.working_set`, formula `A / 8589934592 * 100`, grouped by `service.name` +
`deployment.environment`, filtered on the `alert_threshold.memory` resource attribute.
