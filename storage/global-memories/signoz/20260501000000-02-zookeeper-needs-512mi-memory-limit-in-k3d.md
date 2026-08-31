---
date: 2026-05-01
keywords: ["signoz", "helm", "chart"]
---

## ZooKeeper needs ≥512Mi memory limit in k3d

Default chart ZooKeeper resources (256Mi limit) cause OOMKill on k3d clusters. ZooKeeper's JVM + admin server + data operations exceed 256Mi quickly.
Fix: Set `clickhouse.zookeeper.resources.limits.memory: 512Mi` in signoz-values.yaml.
