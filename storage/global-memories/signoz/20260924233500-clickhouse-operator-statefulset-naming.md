---
date: 2026-09-24
keywords: ["signoz", "clickhouse", "altinity-operator", "statefulset", "naming"]
trigger-on: ["signoz-clickhouse", "clickhouse-operator"]
---

## The ClickHouse operator names its StatefulSet `<chi>-<cluster>-<shard>-<replica>`

A ClickHouse Installation managed by the Altinity operator does not create a StatefulSet named after the CHI (`signoz-clickhouse` → `chi-signoz-clickhouse-cluster`). It appends the shard and replica indices, so the object is `chi-signoz-clickhouse-cluster-0-0`, and the pod is that name plus `-0` (`…-cluster-0-0-0`). Anything deriving the StatefulSet name by concatenating `<chi>-<cluster>` fails with `NotFound` on the first scale or rollout-status call, while the pod name it derived from the pod list still looks right. Discover the StatefulSet from the cluster (the first `chi-*` one in the namespace) rather than deriving it, and take the pod as `<statefulset>-0`.
