---
date: 2026-10-22
keywords: ["signoz", "log-volume", "anomaly", "triage"]
trigger-on: ["signoz-log-volume-anomaly"]
---

## Triaging a log-volume anomaly: count distinct identifiers before believing it

A 3-sigma `Log volume anomaly` on a quiet service is usually amplification, not an incident. Reconstruct the window in five-minute buckets (`signoz_aggregate_logs`, `groupBy=severity_text`, `stepInterval=300`) to find the burst, then pull the rows and group them by message shape.

The decisive step is extracting the identifier inside the message — refresh token, phone number, user id, request id — and counting **distinct** values versus total lines. Thirty-five lines carrying one repeated token means one client retrying, not thirty-five users failing; that single number changes the verdict from incident to noise. Mismatched severity pairs with identical per-bucket counts (e.g. equal INFO and ERROR) mean one business event is logged twice, so check the `context` attribute before treating the ERROR as real.

Also compare the burst against the multi-day daily totals of the same message (daily `time_series` over 7d). A pattern that runs every day and merely spiked in one bucket is chronic behaviour, not a regression — and it usually points at a duplicated log line rather than a fault.
