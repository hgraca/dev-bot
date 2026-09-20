---
date: 2026-09-16
keywords: ['mysql', 'keyset-pagination', 'order-by-desc', 'nulls-last', 'offset']
trigger-on: ['keyset-pagination', 'cursor-pagination-nullable-order', 'replace-chunk-with-keyset']
---

## Keyset pagination over a nullable column ordered DESC needs a separate NULL phase

Swapping `chunk()` (OFFSET) for keyset pagination is the standard fix for deep pagination on a large table — but a **nullable** column ordered `DESC` breaks the naive cursor. MySQL/MariaDB treat NULL as the lowest value, so `ORDER BY col DESC` places NULLs **last**, and a single `(col, id) < (:lastCol, :lastId)` predicate cannot express "the rest of the non-null block, then the null block".

The cursor predicate needs two phases. While the previous row carried a value:

```sql
col < :lastCol OR (col = :lastCol AND id < :lastId) OR col IS NULL
```

Once the previous row's value was NULL, only the null block is left:

```sql
col IS NULL AND id < :lastId
```

Omit the second phase and the boundary between the two blocks silently skips or repeats rows. Two related rules: always add a **unique tiebreaker** (e.g. the primary key) to the ORDER BY — a non-unique sort alone makes OFFSET pagination skip/repeat rows too, and makes the keyset comparison ambiguous — and size each page as `min(pageSize, remaining)` when the caller passes a limit, because a fixed page size overshoots the last batch.

Worth testing at the boundary rather than only on happy paths: a tiny page size (1–2) with rows on both sides of the null transition is cheap and is the only place the bug shows.
