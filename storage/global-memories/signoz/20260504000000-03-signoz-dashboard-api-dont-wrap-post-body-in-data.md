---
date: 2026-05-04
keywords: ["signoz"]
---

## SigNoz dashboard API: don't wrap POST body in {data: .}

The `POST /api/v1/dashboards` endpoint stores the POST body directly as the dashboard's `Data` field (`StorableDashboardData = map[string]interface{}`). If you wrap the JSON in `{data: .}`, the title/widgets end up nested under `data.data` and the UI shows a blank dashboard with null title.
Fix: Send the dashboard JSON directly (title, widgets, layout at top level). See commit 69ae980.
