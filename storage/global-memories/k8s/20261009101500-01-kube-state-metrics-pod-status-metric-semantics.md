---
date: 2026-10-09
keywords: ["k8s", "kube-state-metrics", "kube_pod_status", "pod-status"]
---

## Kube-state-metrics pod-status metrics: the label traps that silently zero a query

Four non-obvious properties of the KSM `kube_pod_status_*` families, each of which makes a plausible query return the wrong answer with no error.

- **`kube_pod_status_ready` carries a `condition` label** (`true`/`false`/`unknown`), each a separate 0/1 series. Aggregating across them (e.g. a `min` space-aggregation) collapses to `0` even for a Ready pod — filter `condition='true'` and test the value instead.
- **`kube_pod_status_phase` emits one 0/1 series per pod per phase.** Filtering `phase='Failed'` keeps a series for every pod (value `1` for Failed pods, `0` otherwise), so summing within a group yields the count of Failed pods. Zero-valued series persist for non-active phases, which is why a group stays present at `0` rather than disappearing.
- **Completed pods report not-Ready.** A `Succeeded` pod (a finished Job/CronJob run) has `kube_pod_status_ready{condition="false"}=1`, so a naive "not Ready" rule is dominated by completed pods. Exclude the terminal phases (`Succeeded`, `Failed`) for a genuine readiness alert.
- **`kube_pod_status_reason{reason="Evicted"}` is a state, not an event.** It keeps reporting the Failed pod object for as long as it lingers, so a rule on it stays firing long after the eviction; alert on the `Evicted` Kubernetes event to catch the moment instead.

Also: the pod-status families carry no `node` label (it lives on `kube_pod_info`), so grouping pod status by node needs a join.
