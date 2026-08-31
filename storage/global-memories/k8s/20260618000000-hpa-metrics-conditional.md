---
date: 2026-06-18
keywords: ["k8s", "hpa", "kube-state-metrics", "prometheus"]
---

## HPA metrics from kube-state-metrics are conditional on HPA objects existing

KSM does not pre-declare metrics for resources that don't exist. `kube_hpa_spec_min_replicas`, `kube_hpa_spec_max_replicas`, `kube_hpa_status_current_replicas`, and `kube_hpa_status_desired_replicas` are only emitted when actual `HorizontalPodAutoscaler` resources are present in the cluster. An empty `kubectl get hpa --all-namespaces` means zero HPA metrics in Prometheus/SigNoz — this is not a misconfiguration, it's KSM's auto-discovery behavior. The same applies to other KSM resource metrics (jobs, cronjobs, etc.). When HPAs are created, metrics appear within ~60s with no config changes needed.
