---
date: 2026-09-30
keywords: ["signoz", "alertOnAbsent", "no-data-alert", "alert-threshold"]
trigger-on: ["signoz-alert-on-absent-data", "signoz-alertonabsent"]
---

## `alertOnAbsent` is additive to the alert threshold, not a replacement

In a SigNoz v2alpha1 `threshold_rule`, enabling `alertOnAbsent` (the UI's "Alert when data stops coming") does not switch the rule into an absence-only mode: the threshold condition is still evaluated, and the rule fires when **either** the threshold is breached **or** data is missing for `absentFor` minutes. The threshold therefore cannot be left as an inert placeholder. A companion "telemetry absent" rule configured with `op: above, target: 0` fires continuously whenever the metric is present and non-zero — the exact opposite of its intent — and does so in the first evaluation cycle after creation, so `absentFor` never elapses (observed: fired 57 seconds after creation, `absentFor: 15`). To build a rule that fires only on absence, give the threshold a condition the live data can never satisfy; for a non-negative gauge aggregated with `max`, `op: below, target: 0` works. Verified against Get-e's self-hosted SigNoz (v0.143.0) on 2026-09-30.
