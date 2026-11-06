---
date: 2026-11-06
keywords: ["sqlite", "length", "bytes", "blob", "utf8"]
aliases: ["length counts characters", "char vs byte size sqlite"]
---

## `length()` counts characters for TEXT - cast to BLOB for bytes

`length(x)` returns characters for a TEXT value and bytes for a BLOB. A byte budget built on `length(data)` over a TEXT column is therefore wrong whenever the payload is not pure ASCII: a CJK-heavy value is up to ~3x the counted size in UTF-8, so a "32 MiB" transaction bound can really write ~96 MB.

Use `length(CAST(data AS BLOB))` wherever the number is a size - WAL budgets, batch limits, storage reports. The same applies to `length(json_extract(...))` when measuring a JSON subtree. Verified while byte-bounding a batched `UPDATE ... json_remove(...)` over multi-megabyte JSON payloads.
