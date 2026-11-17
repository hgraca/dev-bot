---
date: 2026-11-16
keywords: ["aws", "call_boto3", "timestamp", "mcp"]
aliases: ["imagePushedAt", "isoformat AttributeError", "pipelineExecutionId timestamps"]
trigger-on: ["aws-mcp-call-boto3", "audit-code-call-boto3"]
---

## `call_boto3` returns timestamps as strings, not datetimes

The AWS MCP `run_script` sandbox exposes responses through `call_boto3`, and the JSON-ish values it
hands back are **not** the boto3 Python types: timestamps arrive as `str` (e.g.
`imagePushedAt: "2026-11-16T11:56:48.920000+00:00"`, `lastUpdateTime: "2026-11-16T10:42:54+00:00"`).
Calling `.isoformat()` on them raises `AttributeError: 'str' object has no attribute 'isoformat'` and
the whole script dies *after* the API calls already succeeded — the error surfaces as a failed
`run_script` with valid `api_calls`, which reads like an API fault but is not.

Wrap them in `str(...)` when building output, or compare as strings (ISO-8601 sorts lexicographically).
The same class of surprise applies to nested structures: assume standard-library types you can
serialise, not boto3 objects.
