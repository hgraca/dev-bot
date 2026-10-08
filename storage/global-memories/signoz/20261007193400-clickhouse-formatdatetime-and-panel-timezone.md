---
date: 2026-10-07
keywords: ["signoz", "clickhouse", "formatdatetime", "timezone", "dashboard"]
trigger-on: ["signoz-clickhouse-panel", "signoz-dashboard-sql"]
---

## `formatDateTime` is MySQL-style, and a ClickHouse panel does not inherit the page timezone

Two traps when formatting a timestamp inside a SigNoz ClickHouse dashboard panel.

`formatDateTime` uses MySQL specifiers, not strftime: `formatDateTime(ts, '%Y-%m-%d %H:%M')` renders `2026-10-07 19:October` because `%M` is the **month name**; minutes are `%i`. Use `'%Y-%m-%d %H:%i'`.

The page timezone is not applied. SigNoz documents that the selected timezone "does not apply" to ClickHouse queries — time functions use the server timezone, which is UTC (confirmed live: `timezone()` → `UTC`) — so the zone must be pinned in SQL: pass it as the third argument (`formatDateTime(ts, '%Y-%m-%d %H:%i', 'Europe/Amsterdam')`) or via `toTimeZone`. There is no dynamic page-timezone variable. For logs, `timestamp` is `UInt64` **nanoseconds**, so wrap it: `fromUnixTimestamp64Nano(timestamp)`. A DST-safe UTC-offset suffix can be computed rather than hardcoded, so it flips with daylight saving instead of going stale:

    concat(formatDateTime(ts, '%Y-%m-%d %H:%i', tz),
           ' (UTC', if(timeZoneOffset(toTimeZone(ts, tz)) < 0, '-', '+'),
           toString(abs(toInt32(timeZoneOffset(toTimeZone(ts, tz)) / 3600))), ')')
