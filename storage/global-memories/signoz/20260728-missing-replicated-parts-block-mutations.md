---
date: 2026-07-28
keywords: ["signoz", "clickhouse", "replicatedmergetree", "mutations", "missing-parts"]
trigger-on: ["clickhouse-mutations-stuck", "clickhouse-partmutation-zero", "clickhouse-missing-parts"]
---

## ReplicatedMergeTree missing parts cause PartCheckThread loop, blocking all background mutations

When a ReplicatedMergeTree table has missing parts (from unclean shutdown, disk pressure eviction, or manual filesystem deletion), the PartCheckThread enters a tight loop trying to find the missing part on other replicas. In single-replica setups, no replica has the part, so it loops forever hoping a merge will recreate it. This consumes all background executor threads (48 active with PartMutation=0) and blocks ALL TTL mutations across ALL tables. The PartMutation metric stays at 0 despite queued mutations in system.mutations. Fix: identify the problematic table from clickhouse-server logs ("No active replica has part..."), then use `SYSTEM RESTART REPLICA <table>` or drop the affected partition. In emergency, restarting the ClickHouse pod resets the loop.
