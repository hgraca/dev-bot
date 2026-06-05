---
date: 2026-06-16
keywords: ["otel", "kubeletstats", "kubelet_stats", "otel-collector", "breaking-change"]
---

## kubeletstats receiver renamed to kubelet_stats in v0.152.0

In OpenTelemetry Collector Contrib v0.152.0, the `kubeletstats` receiver was renamed to `kubelet_stats` (underscore added). This is a breaking change — at v0.154.0+, the old name fails silently with no error, meaning kubelet metrics stop flowing without any visible indication. Both the receiver definition block (`kubeletstats:` → `kubelet_stats:`) and the pipeline receivers list entry must be updated. Affects any OTel Collector configmap using kubelet metrics.
