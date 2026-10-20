---
date: 2026-10-15
keywords: ["signoz", "metrics", "unix_milli", "last-seen", "time-series"]
aliases: ["metric series recency", "time_series_v4 unix_milli", "last check-in timestamp"]
---

## SigNoz metric-series `unix_milli` is a bucket start, not a recency value

`signoz_metrics.distributed_time_series_v4_1day.unix_milli` reads like a per-series "last seen"
timestamp, but it is the **start of the day bucket** the series belongs to — every series active
in a day carries the same value. Verified live 2026-10-15: a `message_bus.queue.depth` series
returned `unix_milli = 1791849600000` = 2026-10-13 00:00 UTC, while its samples ran across that
whole day.

Consequence: a "last seen at HH:MM" panel or table cannot be built from the series-metadata
tables — `max(unix_milli) GROUP BY series` yields the day, not the moment. Recency has to come
from another signal, such as a time-series graph whose line ends, or an absent-data alert. The
base `distributed_time_series_v4` is still only hour-bucketed, so it does not help either.
