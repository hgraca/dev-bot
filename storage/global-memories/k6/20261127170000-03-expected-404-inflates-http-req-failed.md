---
date: 2026-11-27
keywords: ["k6", "expectedStatuses", "http_req_failed", "thresholds"]
aliases: ["deliberate 404 counts as failure", "http_req_failed inflated", "expected response status"]
trigger-on: ["k6-scenario", "k6-thresholds"]
---

## k6 counts a deliberate 4xx in `http_req_failed` unless the request declares it expected

`http_req_failed` uses `expectedStatuses({min:200,max:399})` by default, so a load test that probes "this token must 404" adds one failure per probe to the same metric every other scenario gates on. The check can pass while the gate fails: with probes at 1 rps beside ~5 rps of real traffic, a 0.5% error budget is exceeded by ~30×, and the run reports a broken box when the box is fine.

Mark the intent at the request:

```js
http.get(url, { responseCallback: http.expectedStatuses(404) });
```

The check still asserts `r.status === 404`, the metric no longer counts it, and a genuine 5xx under the same budget still fails the run. The same trap applies to any scenario mixing deliberate error responses with success traffic — and it is invisible to `k6 inspect`, so only a real run or a stub with a failing request reveals it.
