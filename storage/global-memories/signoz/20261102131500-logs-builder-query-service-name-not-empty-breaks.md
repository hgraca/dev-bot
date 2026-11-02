---
date: 2026-11-02
keywords: ["signoz", "builder-query", "logs", "service.name", "panel-empty"]
aliases: ["logs panel shows no data", "service.name empty filter kills logs query"]
---

## `service.name != ''` in a logs builder query returns zero rows

On a SigNoz logs `builder_query`, adding `service.name != ''` to the filter expression silently empties the panel: the query returns no rows at all (`rowsScanned: 0`), not an error. The same predicate is harmless on the metrics and traces signals, which is why panels copied from `signoz_calls_total` rules break when repointed at logs. Drop it — `service.name IN $service` already excludes unattributed records — and verify with a scalar run before importing the dashboard: combine it with another condition and the empty result looks like "this service logs nothing".
