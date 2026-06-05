---
date: 2026-06-15
keywords: ["otel", "signoz", "k8sattributes", "transform"]
---

## Normalize host.name from k8s.node.name via transform processor

OTel collector's `k8sattributes` processor sets `k8s.node.name` but not `host.name`. SigNoz's Infrastructure tab and logs host-matching rely on `host.name`, so without normalization the Infrastructure tab shows pod names instead of node names and the logs side panel cannot match hosts. Fix: add a `transform/copy-node-hostname` processor with `set(attributes["host.name"], attributes["k8s.node.name"])` for both metric_statements and log_statements, inserted after `k8sattributes` and before any scrub/attribute processors in both the metrics and logs pipelines. The transform processor runs at resource context level.
