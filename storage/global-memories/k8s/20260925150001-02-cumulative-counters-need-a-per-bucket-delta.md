---
date: 2026-09-25
keywords: ["k8s", "prometheus", "counter", "restarts", "metrics"]
trigger-on: ["prometheus-counter-query", "kubernetes-restart-count", "monitoring-analysis"]
---

## A cumulative counter quoted against a lifespan hides the burst that matters

`kube_pod_container_status_restarts_total` is monotonic, so dividing it by a pod's age yields an average that can be wrong by orders of magnitude: a pod reported as "119 restarts over 14 days" (~8.5/day) had in fact **0 restarts for its first five days, then 118 inside a single 18-hour window**, and zero for the 28 hours after — one correlated episode misread as a chronic condition, which very nearly justified provisioning a larger node. Always convert first (`increase(metric[range])`, or the delta between two reads) over fixed buckets before concluding anything. The corollary is that quiet windows are weak evidence in the same way: restart counts arrive in overdispersed storms, so 50-hour and 5-day zero windows occurred naturally in the very dataset being reasoned about, and "0 restarts in 47 minutes" carried a ~40% chance of happening at the old broken rate. The rule generalises to every `*_total` (`container_cpu_cfs_throttled_periods_total`, `*_seconds_total`, request counters): a value without a matching time denominator is not a rate, and a rate is the only thing that can answer "is this still happening?".
