---
date: 2026-10-16
keywords: ["signoz", "anomaly-rule", "alert-rule-api", "outside_bounds", "seasonality"]
aliases: ["above_or_below rejected", "anomaly alert manifest shape", "z_score_threshold"]
trigger-on: ["signoz-anomaly-alert"]
---

## SigNoz anomaly rules take a different manifest shape, and "either direction" is `outside_bounds`

An `anomaly_rule` is not a threshold rule with different numbers — its manifest differs in five places, and the API rejects the obvious guesses:

- **No `schemaVersion`.** Threshold rules carry `v2alpha1`; anomaly rules must omit it.
- **No `thresholds`, no `evaluation`.** The condition carries `algorithm: "standard"`, `seasonality` (`hourly`|`daily`|`weekly`), `op`, `matchType`, `target` (the z-score), and the channel goes in top-level `preferredChannels` (v1 direct routing) rather than per-threshold `channels`.
- **`evalWindow` and `frequency` are top-level on the rule**, not under `condition`. Sending them nested inside `condition` is accepted and silently hoisted to the top level by the server.
- **The anomaly is a query function**: `functions: [{name: "anomaly", args: [{name: "z_score_threshold", value: 3}]}]` on the builder query, alongside `condition.target`.
- **Metric + Query Builder only** — no ClickHouse, no PromQL.

The trap: the `op` meaning "above or below" (deviation in either direction) is **`outside_bounds`**. `above_or_below` — the natural guess, and the wording the UI uses — is rejected with `condition.op: unsupported value "above_or_below"; must be one of above, below, equal, not_equal, above_or_equal, below_or_equal, outside_bounds`. Verified against SigNoz v0.143.0.

An anomaly rule is the only way to catch a **collapse**: every level-based rule reads a drop as "all quiet". The observability repo's `scripts/setup-alerts.sh` needed no change to carry them — it posts each manifest verbatim, branching only on the top-level `alert` key and re-issuing a `PUT` for `disabled: true`.
