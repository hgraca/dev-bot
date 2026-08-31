---
date: 2026-06-18
keywords: ["signoz", "dashboard", "placeholder", "metrics"]
---

## SigNoz dashboard panels can be created as placeholders before metrics exist

SigNoz dashboard panels accept expected metric names even when those metrics don't yet exist in the system. The panel will show "no data" until the metrics appear, then render normally without any configuration change. This is useful for pre-configuring dashboards for features not yet deployed (e.g., HPA panels before autoscaling is set up, application panels before services are instrumented). Use standard KSM/Prometheus metric names — when the resource is created, kube-state-metrics auto-discovers it and starts emitting the metric, which SigNoz picks up automatically.
