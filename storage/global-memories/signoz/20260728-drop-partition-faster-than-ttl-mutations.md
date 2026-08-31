---
date: 2026-07-28
keywords: ["signoz", "clickhouse", "ttl", "drop-partition", "retention"]
trigger-on: ["clickhouse-ttl", "clickhouse-retention", "clickhouse-disk-full"]
---

## DROP PARTITION is orders of magnitude faster than MATERIALIZE TTL for bulk ClickHouse cleanup

When ClickHouse tables have grown to hundreds of GB due to missing TTLs, TTL mutations (MATERIALIZE TTL) are extremely slow — processing 168+ parts through the background pool while competing with regular merges. DROP PARTITION deletes entire date partitions instantly through ClickHouse's internal mechanisms, properly coordinating with ZooKeeper for ReplicatedMergeTree tables. For a 612G table, DROP PARTITION freed 448G in minutes vs TTL mutations that barely made progress in hours. Use DROP PARTITION for emergency cleanup, then apply TTLs for ongoing retention. Example: `ALTER TABLE signoz_traces.signoz_index_v3 DROP PARTITION '2026-07-05'`.
