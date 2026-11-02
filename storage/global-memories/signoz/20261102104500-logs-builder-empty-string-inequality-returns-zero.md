---
date: 2026-11-02
keywords: ["signoz", "query-builder", "exists", "logs-filter"]
aliases: ["empty string filter", "attribute not empty", "k8s.deployment.name != ''", "related_logs empty"]
trigger-on: ["signoz-logs-filter", "signoz-alert-builder-query"]
---

## A logs builder query returns zero rows for `attr != ''` — use `EXISTS`

On a logs-signal Query Builder filter, an empty-string inequality (`k8s.deployment.name != ''`) matches **nothing**: the resource-fingerprint lookup resolves it to an empty candidate set (`rowsScanned: 0`), so the query returns zero rows with no error, while `= 'production'`, `!= 'nope'` and `EXISTS` on the same key all behave correctly. This silently blinds everything built on that filter — a logs threshold rule whose evaluation query uses it never fires (Get-e's `Alert-level logs` missed a real ALERT this way), and an alert's `related_logs` deep link, which is generated from the rule's (usually disabled) logs builder query rather than its ClickHouse SQL query, opens an empty Logs Explorer. Express "attribute is present" as `attr EXISTS`. The trap does not apply to metric queries (where `!= ''` behaves the same as `EXISTS`), to trace queries, or to raw ClickHouse SQL over `distributed_logs_v2`, where `resource.<attr>::String != ''` works.
