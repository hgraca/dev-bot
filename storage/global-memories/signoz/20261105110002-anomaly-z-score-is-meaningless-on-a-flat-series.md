---
date: 2026-11-05
keywords: ["signoz", "anomaly", "z-score", "alerting"]
aliases: ["traffic drop false positive", "anomaly threshold too sensitive", "flat series z-score"]
trigger-on: ["signoz-anomaly-rule"]
---

## A z-score threshold is meaningless on a near-constant series

SigNoz anomaly rules score a series against its own daily pattern, so a service whose throughput barely moves has a tiny spread and ordinary quantisation noise scores far past ±3σ. A service running at ~0.84 spans/s all day (0.75-0.87) fired four times in five days at scores of -3.2 to -5.9 while its rate never left that band; the only genuine fire in the period, a fleet-wide ingestion outage, scored -8.84. Two fixes, in order of preference: raise the rule's `target` (and the function's `z_score_threshold`) until false positives sit below the smallest real event you have measured, or exclude the flat service and give it a dedicated level rule — the second is what this stack already does for its lowest-variance services. Always check the raw metric before trusting the score: query the rate over the fire window at 1-minute resolution. If the series never moved, the alert is the defect, not the service.
