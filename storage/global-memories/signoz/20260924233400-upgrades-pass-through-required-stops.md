---
date: 2026-09-24
keywords: ["signoz", "upgrade", "stops", "clickhouse", "migration"]
trigger-on: ["signoz-upgrade", "signoz-chart-version"]
---

## SigNoz upgrades must pass through required stops, one at a time

SigNoz publishes a version guide only when a release needs migration steps, and the docs are explicit that a required stop cannot be skipped — "the upgrade can fail or leave your instance in an inconsistent state". Between 0.128.0 and 0.143.0 the stops are **0.131.0** (ClickHouse → 25.12.5; a future collector will not run on older ClickHouse, and the on-disk format upgrade is in place and not reversible), **0.135.0** (dashboards convert to V2 and the V1 dashboard APIs retire), **0.137.0** (saved views convert to a typed schema; unrepairable ones lose their fields), and **0.143.0** (requires signoz-otel-collector v0.144.11, adds the `signozspanmapper`/`signozllmpricing` processors to the traces pipeline, and moves login sessions to opaque tokens — every JWT-secret setting is ignored unless `SIGNOZ_TOKENIZER_PROVIDER=jwt` is set alongside it). Each stop must be pinned explicitly, because the default upgrade command takes the newest chart and jumps past them.
