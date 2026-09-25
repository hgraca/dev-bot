---
date: 2026-09-23
keywords: ["signoz", "logs", "traces", "severity"]
trigger-on: ["signoz-log-triage", "signoz-trace-triage"]
---

## SigNoz triage gotchas: trace span cap, ambiguous body, and HTTP-200 error bodies

Four traps when diagnosing a production incident in SigNoz. (1) `signoz_get_trace_details` returns at most 1000 spans, so a span id taken from a UI deep link can be missing from the payload on a large trace — correlate through logs instead: log records carry `trace_id`/`span_id`, so filter logs by `trace_id = '<id>'` (add `severity_text = 'ERROR'` to skip the noise) to see what that request actually logged. (2) A bare `searchText` search matches the `body` key, which exists in two field contexts (attribute and log) and raises an "ambiguous key" warning — results can come back silently empty; filter on explicit fields instead (`attribute.exception_class CONTAINS '...'`, `trace_id`, `severity_number`). (3) Context-prefixed filters are not universally valid: `log.severity_number >= 23` scans 0 rows while the unqualified `severity_number >= 23` scans normally — prefer the unqualified key unless a prefix is needed to disambiguate. (4) A provider can fail with HTTP 200 and an error JSON body, leaving every span `has_error = false` and no error-span to find; detect it from the outbound client span's `http.response.body.size` (MapBox directions: ~57 bytes for `{"code":"NoRoute"}` versus ~1 kB for a real route) plus `server.address`/`http_url`.
