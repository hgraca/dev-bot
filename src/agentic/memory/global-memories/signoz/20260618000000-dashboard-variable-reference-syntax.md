---
date: 2026-06-18
keywords: ["signoz", "dashboard", "variable", "gotcha", "query-builder"]
---

## SigNoz Query Builder filter expressions use `$var` not `{{.var}}`

SigNoz v5 dashboards with QUERY-type variables reference them in Query Builder filter expressions using `$variableName` syntax — NOT Go-template `{{.VariableName}}`. The `{{.}}` syntax is for Legend formatting only and silently fails in filter expressions (dashboard imports cleanly but queries return no data or ignore the variable).

Correct syntax per https://signoz.io/docs/dashboards/using-variables-in-queries: single-select uses `field = $varName`, multi-select uses `field IN $varName` (no parentheses). The `$varName` must match the variable's `name` field, not the SQL column alias. Multi-select variables with `showALLOption: true` expand `IN $var` to include all values when ALL is selected.

Example: variable named `"service"` with multi-select → filter expression `service.name IN $service`. Variable named `"environment"` with single-select → filter expression `deployment.environment = $environment`.
