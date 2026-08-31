---
date: 2026-07-03
keywords: ["signoz", "dashboard", "update", "gotcha"]
trigger-on: ["signoz-dashboard-update", "signoz_update_dashboard"]
---

## signoz_update_dashboard is a full PUT — partial widgets wipe the dashboard

SigNoz dashboard API `signoz_update_dashboard` performs a full PUT, not a PATCH. Sending only a subset of widgets or layout entries replaces the ENTIRE dashboard with that subset — wiping all other widgets, layout, tags, and variables. Always `signoz_get_dashboard` first, modify the full JSON payload, and send the complete object back. Never send partial widget arrays thinking it will merge. Preserving a backup file (JSON dump) before modifying is recommended.
