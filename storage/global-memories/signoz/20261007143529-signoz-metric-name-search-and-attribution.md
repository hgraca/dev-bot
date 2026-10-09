---
date: 2026-10-07
keywords: ["signoz", "metrics", "metric-name", "service.name", "k8s.cluster.name"]
aliases: ["metric catalog", "list_metrics", "groupBy cluster"]
---

## SigNoz metric search is substring-based and per-window — and `service.name` can come from infra metrics

Four traps when verifying a new metric. (1) `signoz_list_metrics` `searchText` is a substring match on the metric name, so `message_bus` never finds `messaging.*` and `message` never finds `messaging` (the letter sequences differ) — search the exact prefix you expect. The catalog is also per-window: a metric appears only once it has data inside the queried range, so a just-deployed metric is invisible at 6h until ingestion catches up but shows at 24h — widen the window instead of concluding it is missing. (2) `service.name` on a metric does not prove the app produced it: kubelet/k8s metrics carry `service.name` via the k8sattributes processor (`k8s.pod.cpu.usage` grouped by `service.name` lists every service), so confirm the producing metric by its own name, not by the service's presence in the field-value list. (3) Separate prod from staging with `k8s.cluster.name` (`gete` vs `gete-dev`); when attributing a series prefer `groupBy k8s.cluster.name`, because a plain `filter k8s.cluster.name = 'gete-dev'` can return 0 while the groupBy shows the same series. (4) Observable OTel gauges are small integers that read `0` when idle — the success signal is the presence of the series, not a non-zero value.
