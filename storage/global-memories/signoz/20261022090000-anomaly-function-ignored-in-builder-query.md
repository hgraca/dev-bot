---
date: 2026-10-22
keywords: ["signoz", "anomaly", "builder-query", "z-score"]
aliases: ["anomaly function returns raw values", "anomaly score missing", "z-score query"]
---

## The `anomaly` query function is silently dropped by the builder-query API

Attaching `functions: [{"name": "anomaly", "args": [{"name": "z_score_threshold", "value": 3}]}]` to a metrics `builder_query` and executing it through the query API returns the **raw metric series**, not anomaly scores — with HTTP success and no warning. A 24h `signoz_calls_total` request intended to reproduce an alert's z-scores came back with values identical to the plain rate query (e.g. `3.233`, matching the raw burst rate at that minute, where a z-score could not equal the rate). So the function is a config-only construct: it is honoured when the rule is evaluated server-side, but cannot be used to re-derive a past score.

Consequence: an alert's recorded score cannot be reproduced from the query API. Do not conclude "the model is wrong" from a failed reproduction, and do not build tooling that assumes the function round-trips. Confirm the function was applied by comparing against the plain aggregation — if the values match, it was dropped. To reason about a score, fall back to the underlying series and its distribution instead.
