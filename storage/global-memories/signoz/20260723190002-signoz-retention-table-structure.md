---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "retention", "TTL", "table-schema"]
---

## Signoz retention: traces use hardcoded TTL seconds, logs use _retention_days field

Traces (`signoz_index_v3`): `TTL toDateTime(timestamp) + toIntervalSecond(N)` — hardcoded, not configurable per-row. Change with `ALTER TABLE … MODIFY TTL toDateTime(timestamp) + toIntervalSecond(259200)` for 3 days.

Logs (`logs_v2`): `TTL toDateTime(timestamp/1e9) + toIntervalDay(_retention_days)` with `_retention_days UInt16 DEFAULT 15`. To force a fixed 3-day retention regardless of the column default: `ALTER TABLE … MODIFY TTL toDateTime(timestamp/1e9) + toIntervalDay(3)`. This overrides the per-row `_retention_days` field.

Metrics (`samples_v4`): 30 days (2592000s), not changed in this incident. All tables use `PARTITION BY toDate(timestamp)` and `ttl_only_drop_parts = 1`.
