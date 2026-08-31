---
date: 2026-07-03
keywords: ["signoz", "helm", "zookeeper", "initContainers", "warning"]
---

## Signoz Helm chart: harmless "zookeeper.initContainers: Not a table" warning

When deploying `signoz/signoz` Helm chart, the warning `coalesce.go:237: warning: skipped value for zookeeper.initContainers: Not a table` appears. This is a chart packaging bug — the zookeeper subchart's default `values.yaml` has `initContainers: []` (list), but its JSON schema expects a table (map). Not fixable from user-supplied values. The warning is harmless and does not affect deployment. Can be safely ignored.
