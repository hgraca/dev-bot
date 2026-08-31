---
date: 2026-08-18
keywords: ["mysql", "index", "text", "varchar", "failed_jobs"]
trigger-on: ["mysql-text-column-index", "index-only-scan"]
---

## MySQL cannot index a TEXT column; narrow it before adding an index

MySQL forbids indexing a TEXT column without a prefix length, so equality/COUNT queries on it fall back to scanning the clustered index — and when the row carries longText blobs (e.g. Laravel `failed_jobs.payload`/`exception`) that scan is expensive. To get index-only scans for `WHERE queue = ?` counts, change the column to `varchar(256)` (utf8mb4 → 1024 bytes, under the 3072-byte InnoDB index limit) and add a plain index on it. Do both in one migration: `->change()` first, then `->index()`.
