---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "zookeeper_log", "system-tables", "TTL"]
trigger-on: ["signoz-disk-consuming", "clickhouse-system-table-bloat", "zookeeper-log-too-large"]
---

## system.zookeeper_log has no TTL and will silently consume disk space

ClickHouse's `system.zookeeper_log` table logs all ZooKeeper coordination operations. It has NO default TTL. On a SigNoz production node (single replica, high insert rate), it grew to 113 GiB (3.35 billion rows, 12% of a 906G disk) over 30 days.

Fix: `TRUNCATE TABLE system.zookeeper_log` (may need `SET max_table_size_to_drop = 0` if table > 50 GiB) then add TTL: `ALTER TABLE system.zookeeper_log MODIFY TTL event_date + INTERVAL 7 DAY`. Check monthly — watch other system tables too (query_log was 8.7 GiB, part_log 3.5 GiB).
