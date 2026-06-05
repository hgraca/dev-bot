---
date: 2026-06-18
keywords: ["signoz", "kubelet", "daemonset", "gotcha", "otel-collector"]
---

## OTel kubelet_stats receiver must run as DaemonSet, not Deployment

The kubelet_stats receiver scrapes kubelets by node IP. When running on a Kubernetes Deployment (single pod), `${K8S_NODE_IP}` resolves at collector config load time to the pod's host IP — the receiver only scrapes that ONE node's kubelet forever. Data from other nodes is only visible when the Deployment pod happened to run on those nodes in the past.

Fix: run as DaemonSet with `hostNetwork: true`, no explicit `endpoint` config. Each DaemonSet pod scrapes its local kubelet via `https://localhost:10250` (default with `auth_type: serviceAccount`). The gateway Deployment should NOT run kubelet_stats — it should handle OTLP, prometheus, k8s_cluster receivers only.

Also: `endpoint: https://${env:K8S_NODE_IP}:10250` resolves at config load, not per-node. Remove the endpoint line entirely for DaemonSet; keep only `collection_interval`, `auth_type`, `insecure_skip_verify`, and `metric_groups`.
