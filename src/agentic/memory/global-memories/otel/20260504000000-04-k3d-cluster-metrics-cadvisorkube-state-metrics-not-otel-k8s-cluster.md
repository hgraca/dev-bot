---
date: 2026-05-04
keywords: ["otel"]
---

## k3d cluster metrics: cadvisor/kube-state-metrics, NOT OTel k8s cluster receiver

The k3d cluster collects metrics via cadvisor (`container_*`) and kube-state-metrics (`kube_*`), NOT the OTel k8s cluster receiver (`k8s_pod_*`, `k8s_node_*`). Labels are Prometheus-style (`namespace`, `pod`, `container`), not OTel semantic conventions (`k8s.namespace.name`, `k8s.pod.name`). Use `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, `kube_pod_container_status_restarts_total`.
Fix: See commit 69ae980 for correct metric names and labels.
