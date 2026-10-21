---
date: 2026-10-21
keywords: ["signoz", "alert-filter", "empty-string", "resource-attributes", "alertOnAbsent"]
aliases: ["!= empty matches nothing", "EXISTS instead of != empty"]
trigger-on: ["signoz-alert-filter", "signoz-absent-rule"]
---

## Comparing a resource field to an empty string matches no rows

In SigNoz v0.143.0 a builder-query filter clause such as `k8s.deployment.name != ""` — and equally `host.name != ""` or `deployment.environment != ""` — matches **zero** rows instead of "rows that have the field", so an `alertOnAbsent` rule built on it fires forever (no span ever satisfies the filter) and a threshold rule built on it can never fire. The same field compared with `= '<value>'` or with `EXISTS` returns the rows. Use `k8s.deployment.name EXISTS` for the "has a value" intent: on the traces index the unattributable spans carry the key **absent** (2.5M spans/day), never present-and-empty (zero rows in 24h), so `EXISTS` preserves the intent and is the only spelling that evaluates. Verify a suspect filter by posting the same builder query through `POST /api/v5/query_range` with and without the clause — `rowsScanned: 0` on the clause version, data on the other, is the signature. A `service.name EXISTS` clause in the same repo's budget rules works, which is a useful control when triaging.
