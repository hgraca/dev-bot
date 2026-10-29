---
date: 2026-10-29
keywords: ["signoz", "traces", "alert-window", "count_distinct"]
---

## A span-count alert window must pay for the run's own length

A span's timestamp is its start time, but the row only becomes queryable when the run ends — so a count rule over spans whose window is exactly N × period drops the first of N slow failures before the Nth lands, and the rule never reaches its threshold on a streak of slow failures. Size it `N × period + longest run + slack`, and count runs with `count_distinct(span_id)` rather than `count()`: the trace store can serve the same span twice (observed: identical `span_id` and timestamp returned as two rows), so a row count lets one failure register as two. Production evidence: a 5-minute scheduler whose failing runs took 4m00s and 6m39s had its first three consecutive failures become queryable 25m38s after the first start, so a 25-minute window needed a fourth failure while a 30-minute one fires; the same filter returned 6 distinct spans for 6 raw rows.
