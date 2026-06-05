---
date: 2026-06-18
keywords: ["signoz", "dashboard", "variable", "metrics", "clickhouse"]
---

## K8s dashboard service variable must query metrics, not traces

Application dashboards use trace-based variable queries (`signoz_traces`), but K8s pod/container dashboards need metrics-based queries. The `service.name` attribute on k8s pod metrics comes from the k8sattributes processor enriching kubelet metrics with pod labels — it does NOT appear in traces.

Correct metrics query for service dropdown on K8s dashboards:

```sql
SELECT DISTINCT JSONExtractString(labels, 'service.name') AS `service.name`
FROM signoz_metrics.distributed_time_series_v4_1day
WHERE JSONExtractString(labels, 'service.name') != '' LIMIT 100
```

For environment:

```sql
SELECT DISTINCT env AS value FROM signoz_metrics.distributed_time_series_v4_1day WHERE env != '' LIMIT 100
```

Using trace-based queries on K8s dashboards only shows services that send OTel traces (not infrastructure-only services).
