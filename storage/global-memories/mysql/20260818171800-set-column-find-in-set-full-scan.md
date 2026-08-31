---
date: 2026-08-18
keywords: ["mysql", "find-in-set", "set-column", "full-scan", "index"]
trigger-on: ["find-in-set", "set-column", "full-table-scan", "composite-index"]
---

## `FIND_IN_SET` over a `SET` column forces a full scan; a range index on other columns narrows it

`FIND_IN_SET(?, applicable_on_days)` over a MySQL `SET` column can never use an index, so a predicate like `start <= ? AND end >= ? AND (applicable_on_days IS NULL OR FIND_IN_SET(...) ...)` full-scans the table on every call (seen in the transfers stop-sales lookup). Fix: add a composite index on the range columns — `(start, end)` — so the `start`/`end` overlap becomes an index range scan and the day/time predicates are pushed down with index condition pushdown, evaluating `FIND_IN_SET` only on the already-narrowed rows. Also note: comparing a `TIME` column (`applicable_start_time`) to a bound datetime string is *correct* — MySQL coerces the datetime to its time-of-day portion, so `applicable_start_time <= '2026-08-18 09:00:00'` really compares `'18:00:00' <= '09:00:00'`; do not "fix" it by extracting the time in PHP.
