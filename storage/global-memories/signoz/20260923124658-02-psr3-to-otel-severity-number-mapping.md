---
date: 2026-09-23
keywords: ["signoz", "severity", "monolog", "alerting"]
trigger-on: ["signoz-severity-filter", "psr3-log-level-mapping"]
---

## PSR-3 log levels reach SigNoz as OTel severity_number = level / 25 + 1

This app's PSR-3/Monolog levels land in SigNoz as OTel `severity_number = level / 25 + 1`: debug 100→5, info 200→9, notice 250→11, warning 300→13, error 400→17, critical 500→21, alert 550→23, emergency 600→24 (clamped). So "all alert-level logs" is `severity_number >= 23` (alert plus emergency) and deliberately excludes critical at 21 — a rule meant to fire on alert-level lines must filter 23, not the 21 that `critical` produces. `severity_text` mirrors the level name but its casing is not consistent across services (`ERROR` from the PHP pods, lowercase `warn` from the Go services), so filter on the numeric field. Confirm empirically before trusting the formula: `signoz_get_field_values(signal=logs, name=severity_number, fieldContext=log)` lists only observed values.
