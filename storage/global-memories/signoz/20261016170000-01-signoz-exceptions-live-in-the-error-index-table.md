---
date: 2026-10-16
keywords: ["signoz", "exceptions", "span events", "error index", "clickhouse"]
aliases: ["exception.type returns no rows", "Exceptions tab empty", "signoz_error_index_v2"]
trigger-on: ["signoz-exceptions-verification"]
---

## Verify SigNoz exceptions via the error-index table, not an `exception.type` trace field

SigNoz builds its **Exceptions** view from span `exception` events, which are materialised into `signoz_traces.signoz_error_index_v2` (columns `exceptionType`, `exceptionMessage`, `exceptionStacktrace`, `exceptionEscaped`, `groupID`, `serviceName`, `traceID`, `spanID`, `resourceTagsMap`; distributed twin `distributed_signoz_error_index_v2`) — **not** into `signoz_index_v3`, whose only exception-bearing column is the raw `events: Array(String)`. `exception.type` is therefore absent from `signoz_get_field_keys(signal=traces)`, and a Query-Builder filter on it can never match: "0 rows for `exception.type`" is a false negative, not proof that nothing is recorded. To check reality, query the store directly — `signoz_execute_builder_query` accepts a `clickhouse_sql` composite, e.g. `SELECT exceptionType, count() AS c, min(timestamp), max(timestamp) FROM signoz_traces.distributed_signoz_error_index_v2 WHERE serviceName='<svc>' AND timestamp >= now() - INTERVAL 1 DAY GROUP BY exceptionType ORDER BY c DESC`. Group by `resourceTagsMap['k8s.pod.name']` to attribute an error to a specific pod, and check `length(exceptionStacktrace)` when judging whether stack traces are captured. Only a service whose spans genuinely carry no `exception` event shows zero rows.
