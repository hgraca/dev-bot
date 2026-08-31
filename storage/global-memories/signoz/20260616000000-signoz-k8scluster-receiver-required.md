---
date: 2026-06-16
keywords: ["signoz", "k8scluster", "k8s", "otel"]
---

## SigNoz Kubernetes Monitoring requires k8scluster OTel receiver

SigNoz's Kubernetes Infrastructure view (Nodes, Deployments, StatefulSets, DaemonSets, Jobs) requires metrics from the `k8s_cluster` OTel receiver — Prometheus-scraped KSM metrics alone are insufficient. Without `k8s_cluster`, only CPU/memory from kubeletstats shows; entity views are blank even if KSM data exists in ClickHouse. The receiver produces metrics with entity UIDs (`node.uid`, `pod.uid`) that SigNoz UI requires for entity resolution. Must run as single Deployment replica per cluster (singleton constraint — not DaemonSet). Also needs expanded RBAC: `apps/{statefulsets,daemonsets}` and `batch/{jobs,cronjobs}` with get/list/watch.
