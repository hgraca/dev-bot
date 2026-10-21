---
date: 2026-10-21
keywords: ["signoz", "anomaly", "logs", "count-connector", "log-volume"]
aliases: ["log volume anomaly", "logs signal anomaly", "log growth anomaly"]
---

## Anomaly detection is metric-only — give log volume a metric face

`anomaly_rule` accepts only Query Builder **metric** queries (no ClickHouse, no PromQL, no logs signal), so a log-growth spike can never trigger one, however the threshold is tuned. Log volume only becomes an anomaly candidate once it exists as a metric; the cheapest place to derive it is the OTel gateway every producer's logs pass through, with the `count` connector emitting a log-record count dimensioned by `service.name`, `deployment.environment` and `k8s.deployment.name`. Threshold rules that compare against the previous minute cannot substitute: sustained growth under 20%/min never trips them, however far the volume climbs over an hour (2× per hour is +1.2%/min), and they false-positive on periodic bursts.
