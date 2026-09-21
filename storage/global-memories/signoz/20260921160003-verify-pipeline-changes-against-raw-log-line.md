---
date: 2026-09-21
keywords: ["signoz", "log-line", "verification", "severity-proxy", "save-log-line"]
trigger-on: ["signoz-log-verification", "severity-based-filter"]
---

## Verify collector pipeline changes against the raw `log_line`, never against derived severity

When a collector's `save-log-line` operator stores the pre-parse line in `attributes["log_line"]`, that attribute is model-independent: it is written before any severity derivation, so it reads identically whichever severity model the cluster runs. That makes it the only reliable basis for before/after comparison across a pipeline change — counting rows whose raw line contains `"level_name":"CRITICAL"` proves where the application's own level landed regardless of how the collector rewrote it. Conversely, never classify *kinds* of log line by derived severity: `severity_text IN ('WARN','NOTICE')` looks like "all 4xx access logs" but also matches nginx **error-log** `[warn]` lines, which carry no `status` attribute at all — a mixed set that can make a severity reclassification look like a traffic collapse. Filter on the raw `log_line`, or on an attribute that actually distinguishes the kinds, and sample the results before trusting any aggregate that spans more than one log format.
