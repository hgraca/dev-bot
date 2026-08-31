---
date: 2026-06-18
keywords: ["signoz", "k8sattributes", "pod_association", "otel"]
---

## k8sattributes processor needs k8s.pod.name fallback for pod association

The k8sattributes processor enriches telemetry with pod labels by associating metrics/spans to pods. Default association uses `k8s.pod.uid` and `k8s.pod.ip`. However, kubelet_stats receiver often doesn't populate either — only `k8s.pod.name` is set on kubelet pod/container metrics.

Without `k8s.pod.name` in `pod_association`, the processor silently fails to enrich metrics with labels like `service.name`. Fix: add all three association sources:

```yaml
pod_association:
    - sources:
          - from: resource_attribute
            name: k8s.pod.uid
    - sources:
          - from: resource_attribute
            name: k8s.pod.ip
    - sources:
          - from: resource_attribute
            name: k8s.pod.name
```

Also ensure `k8s.pod.name` is in the `extract.metadata` list so the processor knows to look it up.
