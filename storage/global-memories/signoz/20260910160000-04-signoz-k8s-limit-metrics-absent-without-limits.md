---
date: 2026-09-10
keywords: ["signoz", "k8s", "kube-state-metrics", "resource-limits", "utilization"]
trigger-on: ["signoz-k8s-limit-alert", "k8s-pod-limit-utilization"]
---

## K8s limit metrics are absent for pods/containers without limits

`kube_pod_container_resource_limits` (KSM) is only emitted for containers that explicitly set a limit, and `k8s.pod.{cpu,memory}_limit_utilization` is only emitted when every container in the pod has a limit — so pods without limits produce no series and are invisible to alerts built on those metrics. A "pod missing a limit" check therefore cannot use `min(...) == 0` (that only catches explicit zeros); detect omission by comparing container inventory against limit series (`count(kube_pod_container_info)` vs `count(kube_pod_container_resource_limits)`, or PromQL `unless`). Requests behave the same way (`k8s.pod.*_request_utilization` absent without requests).
