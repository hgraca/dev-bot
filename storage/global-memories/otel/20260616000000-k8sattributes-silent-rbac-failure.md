---
date: 2026-06-16
keywords: ["otel", "k8sattributes", "rbac", "k8s"]
---

## k8sattributes silently drops owner-reference fields on RBAC 403

The `k8sattributes` OTel processor resolves pod ownerReferences to populate `k8s.statefulset.name`, `k8s.daemonset.name`, `k8s.job.name`, `k8s.cronjob.name`. When the collector's ServiceAccount lacks RBAC for these resource types (apps/statefulsets, apps/daemonsets, batch/jobs, batch/cronjobs), k8sattributes silently skips the field on 403 — it does NOT log an error. The fields simply remain empty. This causes a silent data gap: telemetry flows but entity names are missing, and the failure only surfaces when downstream consumers (SigNoz UI, dashboards) show blank entity names. Prevention: always verify RBAC covers all owner-reference resource types when adding k8sattributes metadata extraction fields.
