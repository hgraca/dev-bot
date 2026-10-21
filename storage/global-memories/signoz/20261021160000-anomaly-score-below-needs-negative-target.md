---
date: 2026-10-21
keywords: ["signoz", "anomaly", "z-score", "below", "alerting"]
aliases: ["anomaly drop rule", "outside_bounds direction", "negative target"]
---

## Anomaly score is signed; `op: below` needs a negative target

SigNoz anomaly rules evaluate the condition against a signed z-score: a series above its forecast scores positive, a drop scores negative (observed live: `-0.41`). `op: below` with a positive `target` therefore matches every ordinary value below +Nσ and fires constantly — a `below`/`target: 3` rule armed at 09:19 paged for six services at once on ordinary traffic, all with scores between `-0.41` and `+2.16`. To detect drops only, set `target` to the negative threshold (`op: below`, `target: -3`). `op: outside_bounds` compares the magnitude, so it cannot express direction; `op: above` with a positive target is a genuine spike rule. `{{$value}}` is the score, never the metric value, so it supplies neither direction nor real units — a level threshold rule is the way to get reqps/bytes into the message.
