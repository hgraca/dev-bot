---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "ALTER TABLE", "timeout", "mutation"]
trigger-on: ["clickhouse-alter-table-hang", "clickhouse-ddl-timeout"]
---

## ClickHouse ALTER TABLE MODIFY TTL may time out but still succeed

When the merge pool is saturated (26 concurrent merges), `ALTER TABLE … MODIFY TTL` can take 120s+ and the clickhouse-client connection times out. However, the DDL is still submitted as a mutation. Check `system.mutations` — if `(MATERIALIZE TTL)` appears with `is_done = 0`, the ALTER was accepted and will process once merge capacity frees up. Use `--receive_timeout=600` on the clickhouse-client for large ALTER operations during heavy load, or just check mutations after a timeout.
