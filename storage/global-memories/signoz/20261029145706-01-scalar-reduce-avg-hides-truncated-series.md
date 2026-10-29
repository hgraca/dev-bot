---
date: 2026-10-29
keywords: ["signoz", "scalar", "reduce-to", "metric-query"]
aliases: ["reduceTo avg misleading", "scalar averages available samples"]
---

## A SigNoz scalar query averages the samples that exist, not the whole window

`requestType: scalar` with the default `reduceTo: avg` divides by the number of samples the series actually returned inside the window — not by the number of buckets the window contains. A series that ends early therefore reports a fraction that reads like "failing a fraction of the time" but is really "the mean over the handful of samples before it disappeared".

Observed 2026-10-29 on a `kube_pod_status_phase{phase="Failed"}` query over 20 minutes: a pod that was `Failed` for exactly one 60s scrape then deleted reported `0.333`, i.e. 1 of 3 samples rather than 1 of 20. Another series with 11 samples reported `0.0909`. Reading those as time-share says the pods were failing for 7 and 2 minutes; they were failing for one minute each and were then garbage-collected.

Use `requestType: time_series` with an explicit `stepInterval` (60s for pod-state work) to read the actual state per bucket — a lingering object keeps reporting `1`, a deleted one's series simply ends. If a scalar is genuinely wanted, set `reduceTo: max` for "did this ever happen in the window" and `reduceTo: last` for "is it happening now"; neither is fooled by a short series. The same trap applies to any `spaceAggregation`/`timeAggregation` pair whose result you then reduce.
