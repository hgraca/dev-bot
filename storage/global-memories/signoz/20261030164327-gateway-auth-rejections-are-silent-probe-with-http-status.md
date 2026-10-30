---
date: 2026-10-30
keywords: ["signoz", "otlp", "bearertokenauth", "alertmanager", "ingestion"]
aliases: ["gateway 401 silent", "cron alerts all fire at once", "no data alert stuck"]
---

## Gateway auth rejections are silent — probe with an HTTP status, not logs

An OTel collector gateway with `bearertokenauth` logs nothing when it rejects a request: the pod log holds only startup lines, so "grep the logs for auth failures" proves nothing and a rejection looks like a dead pipeline. Probe the receiver instead and read the status code: `curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{}' http://<host>:4318/v1/logs` answers `401` with a body naming the failure (`missing or empty authorization header` vs `provided authorization does not match expected scheme or token`) and `200` once the token is accepted — the empty payload, not the credential, is what fails then. A vendor-agnostic trap to remember: on a `[No data]`/`alertOnAbsent` rule group, firing is immediate but resolution lags — alert instances stay `state: active` for roughly two to three evaluation cycles after data returns, so re-poll instead of assuming the rule is stuck; and when every absence rule in a group fires at once, suspect one shared ingestion outage rather than N independent failures, because absence rules cannot distinguish a stopped producer from a stopped pipeline.
