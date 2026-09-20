---
date: 2026-09-11
keywords: ["signoz", "alert-rule", "formula", "disabled", "chart"]
trigger-on: ["signoz-alert-rule", "signoz-alert-formula", "signoz-query-builder"]
---

## SigNoz alert chart plots every enabled query — disable the raw query when a formula is selected

A SigNoz alert whose `selectedQueryName` points at a `builder_formula` (e.g. `A / 134217728 * 100`) still returns and plots **every enabled query** in `compositeQuery.queries` — the chart is built from all result series, not just the selected one (`ChartPreview` renders `prepareChartData(queryResponse.data.payload)` with no filter on `selectedQueryName`). Left enabled, the raw component query `A` is drawn alongside the formula; with the panel unit `percent`, a ~45 MB byte value renders as `45000000%`, dominating the y-axis while the formula line (0–100) is squashed flat. Fix: set `"disabled": true` on the component query's spec — the formula still evaluates because it references `A` explicitly, and SigNoz's own v5 example payloads disable the component queries. See SigNoz/signoz#9512 ("forget to disable the other queries … results in showing the value of A").
