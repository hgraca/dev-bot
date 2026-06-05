---
date: 2026-07-23
keywords: ["signoz", "clickhouse", "error-243", "DiskUnreserved", "merge-pressure"]
trigger-on: ["clickhouse-cannot-reserve", "clickhouse-error-243"]
---

## ClickHouse error 243 "Cannot reserve" is about DiskUnreserved, not DiskAvailable

Error `code: 243, message: Cannot reserve X MiB, not enough space` does NOT mean the disk is full. Check `system.asynchronous_metrics` for `DiskUnreserved_default` — if it's 0, all free disk is reserved by active merges (the merge pool books disk space for safety). `DiskAvailable_default` may show 100+ GiB free while writes still fail.

Fix: reduce `max_bytes_to_merge_at_max_space_in_pool` from default 150 GiB to 50 GiB via `ALTER TABLE … MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 53687091200` (persists in ZooKeeper for ReplicatedMergeTree). On 900G SSD with signoz_index_v3 at 365 GiB and 484 parts, this freed DiskUnreserved from 0 to 58 GiB within minutes.
