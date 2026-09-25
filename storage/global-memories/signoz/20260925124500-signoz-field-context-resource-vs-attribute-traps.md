---
date: 2026-09-25
keywords: ["signoz", "field-context", "group-by", "query-builder", "k8sattributes"]
trigger-on: ["signoz-query-groupby", "signoz-alert-groupby"]
---

## Query Builder group-by field context is per-signal, and a wrong context fails silently

`fieldContext` on a Query Builder `groupBy` entry cannot be inferred from the attribute name, and getting it wrong does not raise an error — it yields an empty label that silently drops the group. Two cases verified against live Kubernetes data:

- **`kube_node_status_condition`: use `node`, not `k8s.node.name`.** The KSM metric carries the node name as an **attribute** (`node`), not as the resource attribute `k8s.node.name`. Grouping by `k8s.node.name` returns an empty string for every node; grouping by `node` returns the real node names. Its other attributes are `condition` and `status`; its resources include `deployment.environment`, `service.name` and `k8s.cluster.name`, and there is **no `job`**.
- **Kubernetes event logs: `k8s.namespace.name` is an `attribute`, not a `resource`.** The k8sevents receiver writes `k8s.namespace.name` into `attributes_string` while `k8s.node.name` and `deployment.environment` land in `resources_string`. With `fieldContext: "resource"` the namespace label is `null` for every one of 237 `Evicted` events over 7d; with `"attribute"` it is `default` for all 237.

## The probe that does not catch this

`signoz_aggregate_logs` and the other helper tools infer the field context themselves, so a probe through them validates the field **name** and returns real values — while the explicit `fieldContext` you then write into a manifest is never exercised. A group-by probe through a helper therefore proves the key exists, not that the declared context is correct. Verify the context explicitly, or read `signoz_get_field_keys`, which lists each key together with its own `fieldContext`.
