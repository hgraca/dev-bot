---
date: 2026-06-15
keywords: ["signoz", "infrastructure", "host.name", "k8s.node.name", "transform"]
---

## SigNoz Infrastructure tab needs host.name = node name for logs/traces side panel

When `host.name` on metrics doesn't match the host identifier used in logs, the Infrastructure tab's side panel (logs/traces tabs) won't populate. In Kubernetes, the `resourcedetection` processor sets `host.name` from the pod's `/proc/sys/kernel/hostname` (pod hostname like `otel-collector-tqkhd`), while logs carry `k8s.node.name` from the k8sattributes processor. Fix: add `transform/copy-node-hostname` processor after `k8sattributes` in both metrics and logs pipelines, using `set(attributes["host.name"], attributes["k8s.node.name"])`. This normalizes `host.name` to the actual Kubernetes node name, enabling both infrastructure tab display and side panel log matching.
