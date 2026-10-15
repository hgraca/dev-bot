---
date: 2026-10-15
keywords: ["signoz", "dashboard", "panel", "clickhouse", "bar-chart"]
aliases: ["ListPanel rejects ClickHouseSQL", "bar panel renders empty", "no column hiding"]
trigger-on: ["signoz-dashboard-panel", "signoz-clickhouse-panel"]
---

## A SigNoz panel validates the query kind it is given, and fails silently when it cannot plot it

A panel's plugin kind is checked against its query kind, and the failure modes differ sharply: `signoz/ListPanel` refuses a raw SQL query outright (`HTTP 400: query kind "signoz/ClickHouseSQL" is not supported by panel kind "signoz/ListPanel"`), so ClickHouse-backed data can only reach Table, Number, Bar, TimeSeries, Histogram or Pie panels. Chart panels additionally expect **time-series** input — a `signoz/BarChartPanel` fed a grouped `scalar` query (category + value) renders **empty with no error at all**, and only works once the query is bucketed to `ts` + series + `value` with kind `time_series`. Table panels have **no column-visibility setting** (their documented configuration is only panel time preference, decimal precision, column units, context links and thresholds), so the one way to hide a column is to stop selecting it. Check the panel/query pairing first whenever a dashboard panel is blank.
