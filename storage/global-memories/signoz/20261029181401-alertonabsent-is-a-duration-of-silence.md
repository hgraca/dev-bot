---
date: 2026-10-29
keywords: ["signoz", "alertOnAbsent", "absentFor", "evalWindow"]
---

## absentFor is a duration of silence, not a threshold value

`condition.absentFor` sets how long data must have stopped arriving before an `alertOnAbsent` rule fires, measured from the last datapoint — confirmed in production: a rule with `absentFor: 20` on a 15-minute job fired exactly 20 minutes after `lastSeen`, with its 5-minute `evalWindow` doing nothing to the horizon. So "N skipped runs" is expressed as `absentFor = N × period + margin`, never by widening `evalWindow`; the window stays at the query's natural lookback, and the threshold is left as a condition live data can never satisfy (`all_the_times below 0`) because `alertOnAbsent` is additive. Corollary for a sparse job: if the threshold is a live trigger instead (e.g. `in_total below 1`), widening the window to reach N periods changes when it fires — that path measures runs in the window, not silence.
