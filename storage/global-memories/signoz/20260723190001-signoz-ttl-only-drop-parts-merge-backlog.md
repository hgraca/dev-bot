---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "ttl_only_drop_parts", "merge-backlog", "retention"]
trigger-on: ["signoz-retention-not-working", "ttl-cleanup-stalled", "old-data-not-dropping"]
---

## Signoz ttl_only_drop_parts=1 blocks TTL cleanup when merge backlog exists

Signoz tables use `SETTINGS ttl_only_drop_parts = 1`. This means TTL only drops a part when ALL rows in that part are past the TTL. With many small unmerged parts (484 on signoz_index_v3), individual parts contain mixed-date data, so no single part fully expires. Old data accumulates, disk fills, merges can't keep up → death spiral.

Best fix: reduce retention (ALTER TABLE MODIFY TTL) + reduce max_bytes_to_merge_at_max_space_in_pool simultaneously. Once merge pool frees up, MATERIALIZE TTL mutations process partitions and drop eligible data. OPTIMIZE FINAL on old partitions helps compact them so TTL can drop them — but only run it when DiskUnreserved > 100 GiB and merges < 10, otherwise it crashes ClickHouse.
