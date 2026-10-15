---
date: 2026-10-15
keywords: ["signoz", "exceptions", "error-index", "groupID", "stacktrace"]
aliases: ["/exceptions page source", "distributed_signoz_error_index_v2"]
trigger-on: ["signoz-exceptions-dashboard"]
---

## SigNoz's Exceptions page reads one ClickHouse table, and that table carries no file paths

The built-in **Exceptions** view (and any exceptions-based alert) is served by `signoz_traces.distributed_signoz_error_index_v2`, whose 11 columns are `timestamp, errorID, groupID, traceID, spanID, serviceName, exceptionType, exceptionMessage, exceptionStacktrace, exceptionEscaped, resourceTagsMap` — note it has **no `ts_bucket_start`** (bound it with `timestamp BETWEEN $start_datetime AND $end_datetime`) and **no attribute maps**, resource attributes living in `resourceTagsMap` only. Rows are derived from span exception events, and `groupID` fingerprints service + type + exact message, so an id embedded in the message yields one `groupID` per occurrence; the collector's `lowCardinalityExceptionGrouping` narrows that to service + type. `exceptionStacktrace` holds **basenames only** — over a 7-day window 0 of 211,047 rows carried `/app/` or `/vendor/`, and the raw span event's `exception.stacktrace` carries none either — so no query can produce a full source path, and the only lever for a readable issues view is grouping on a normalized message (folding uuids, hex ids and digit runs collapsed 4,867 raw groups to 775 issues).
