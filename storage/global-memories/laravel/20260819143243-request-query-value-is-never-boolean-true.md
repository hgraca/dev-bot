---
date: 2026-08-19
keywords: ["laravel", "request", "query-string", "boolean", "dead-code"]
trigger-on: ["request-query-boolean", "laravel-boolean-query-param"]
---

## $request->query('flag') !== true is always true; use $request->boolean()

Query-string values are always strings (or null when absent), never the PHP boolean `true`, so a guard like `$request->query('flag') !== true` evaluates to `true` for every possible value and the guarded branch becomes dead code — the flag can never take effect. For boolean query params use `$request->boolean('flag')`, which runs `filter_var(..., FILTER_VALIDATE_BOOLEAN)` and matches "1"/"true"/"on"/"yes". This is the established pattern across the codebase (e.g. `Presentation/Http/Api/Backoffice/*`).
