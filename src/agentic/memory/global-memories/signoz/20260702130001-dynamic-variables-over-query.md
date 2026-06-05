---
date: 2026-07-02
keywords: ["signoz", "dashboard", "variables", "dynamic", "query"]
trigger-on: ["signoz-dashboard-variables", "signoz-variable-error", "something-went-wrong-filter"]
---

## SigNoz dashboard QUERY-type variables with raw ClickHouse SQL are brittle — prefer DYNAMIC type

Dashboard variables of type `QUERY` that use raw ClickHouse SQL (`SELECT DISTINCT resources_string['deployment.environment'] AS value FROM signoz_traces.distributed_signoz_index_v3`) are fragile across SigNoz versions and user permissions. They cause `Something went wrong` errors and fail with `ERR_NETWORK_CHANGED`. Column names like `resource_string_service$$name` encode dots with `$$` which may not be stable. Use `type: "DYNAMIC"` variables instead, with `dynamicVariablesSource: "Traces"` and `dynamicVariablesAttribute` set to the OTel resource attribute name (e.g. `"deployment.environment"`, `"service.name"`). DYNAMIC variables use SigNoz's built-in field API and auto-discover values without ClickHouse access.
