---
date: 2026-06-15
keywords: ["otel", "hostmetrics", "k8sattributes", "k8s.node.name", "resourcedetection"]
---

## k8sattributes doesn't set k8s.node.name on hostmetrics metrics

The `k8sattributes` processor enriches telemetry by associating source IPs or pod attributes to Kubernetes metadata. For `hostmetrics` receiver metrics, there's no pod association (no source IP, no pod UID) — the metrics come from the node via /proc reads. As a result, `k8sattributes` does NOT set `k8s.node.name` on hostmetrics data.

For DaemonSet collectors, use `resource/inject-environment` processor with `${env:K8S_NODE_NAME}` (from downward API `spec.nodeName`) to set `host.name` directly, overriding the pod hostname set by `resourcedetection`. This works because the DaemonSet runs one pod per node, so `K8S_NODE_NAME` reliably identifies the node.

For logs (filelog receiver), `k8sattributes` CAN associate via pod UID extracted from log file paths, so `transform/copy-node-hostname` (copying `k8s.node.name` → `host.name`) works correctly for logs.
