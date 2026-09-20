---
date: 2026-09-11
keywords: ["otel", "k8sattributes", "resource-attribute", "pod-label", "tag_name"]
trigger-on: ["otel-k8sattributes-extract", "otel-resource-attribute-rename"]
---

## k8sattributes `tag_name` decouples the emitted attribute from the pod label key

In the OpenTelemetry Collector `k8sattributes` processor, each `extract.labels` entry maps a pod label (`key`) to a resource attribute named by `tag_name`. Renaming the Kubernetes pod label does **not** change the emitted attribute unless `tag_name` is changed too — e.g. `key: gete.io/alert-threshold-cpu` with `tag_name: soft_limit.cpu` still emits `soft_limit.cpu`. So a label rename can be made transparent (keep `tag_name`) or propagated (change `tag_name`); decide deliberately, and if you change `tag_name`, every downstream query (alerts, dashboards) must be updated in lockstep or it returns no data until the collector is redeployed and pods restart.
