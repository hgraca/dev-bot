---
date: 2026-06-17
keywords: ["otel", "filelog", "daemonset", "serviceaccount", "clusterrole"]
---

## OTel Collector daemonset with filelog receiver only needs ServiceAccount

When deploying an OTel Collector as a DaemonSet with the filelog receiver (reading logs from host-mounted `/var/log/` paths), only a ServiceAccount is needed — no ClusterRole or ClusterRoleBinding. The filelog receiver reads from the host filesystem and does not make Kubernetes API calls. The k8sattributes processor in daemonset mode discovers pod metadata via the PodIP directly to the kubelet API, not through Kubernetes RBAC. Over-permissioning with ClusterRole (pods, nodes, namespaces, endpoints, events) is unnecessary and should be stripped.
