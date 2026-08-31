---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "OPTIMIZE FINAL", "merge-backlog", "crash"]
trigger-on: ["clickhouse-optimize-final-crash", "clickhouse-shutdown-is-called"]
---

## OPTIMIZE FINAL crashes ClickHouse during heavy merge backlog

Running `OPTIMIZE TABLE … PARTITION '…' FINAL` on a 22 GiB partition (21 parts) while 26 merges are active caused ClickHouse to crash with error 236: "Shutdown is called for table". The table was in the middle of a merge when the OPTIMIZE tried to force additional compaction.

Only run OPTIMIZE FINAL when: `DiskUnreserved_default > 100 GiB`, active merges < 10 (`SELECT count() FROM system.merges`), and no pending MATERIALIZE TTL mutations. Use the `scripts/clickhouse-optimize-final.sh` helper which checks these preconditions and supports `--dry-run`.
