---
date: 2026-06-15
keywords: ["otel", "resourcedetection", "k8s"]
---

## resourcedetection system detector returns pod name in K8s containers

The `resourcedetection` processor with `system` detector in a containerized OTel collector running in Kubernetes returns the container's hostname, which is the **pod name** (e.g., `otel-gateway-5d8f7b6c9-x2k3m`), not the K8s node hostname. This is because the container inherits the pod's hostname, not the node's. For `host.name` on telemetry data, use `k8s.node.name` (from the `k8sattributes` processor) instead — it contains the actual K8s node name (e.g., `ip-10-135-45-42.eu-central-1.compute.internal`). Copy `k8s.node.name` to `host.name` via a `transform` processor placed after `k8sattributes` in the pipeline.
