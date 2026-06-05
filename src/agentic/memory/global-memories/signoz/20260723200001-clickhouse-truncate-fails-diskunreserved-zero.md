---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "truncate", "DiskUnreserved", "catch-22"]
trigger-on: ["clickhouse-truncate-fails", "clickhouse-cannot-truncate"]
---

## TRUNCATE TABLE fails with error 243 when DiskUnreserved = 0

When ClickHouse has DiskUnreserved = 0 (all free space reserved by merges), even a `TRUNCATE TABLE` fails with `code: 243: Cannot reserve 1.00 MiB, not enough space`. The TRUNCATE operation itself needs a small disk reservation to commit metadata changes.

Workaround: reduce `max_bytes_to_merge_at_max_space_in_pool` first to free DiskUnreserved (> 50 MiB is enough), then run the TRUNCATE. Also note: ClickHouse has a safety limit `max_table_size_to_drop = 50 GiB` — tables larger than this require `SET max_table_size_to_drop = 0` before TRUNCATE.
