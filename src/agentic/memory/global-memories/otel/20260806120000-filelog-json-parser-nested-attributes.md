---
date: 2026-08-06
keywords: ["otel", "filelog", "json_parser", "stanza"]
trigger-on: ["json-parser-nested-attributes", "parse-json-attribute-string"]
---

## Parse nested JSON string attribute into flattened top-level attributes with json_parser

When a log attribute contains a serialized JSON string (e.g. `attributes.context = '{"key":"val"}'`), use a second `json_parser` operator with `parse_from: attributes.<key>` and `parse_to: attributes` (flat). The stanza field type supports dot-notated nested paths in `parse_from`. The operator defaults to `on_error: send`, so missing or invalid JSON passes through unchanged.

**Do NOT use `parse_to: attributes.<key>` (nested)** — SigNoz ClickHouse serializes nested attribute maps back to JSON strings on store, undoing the parse. Always flatten to top-level attributes. See also: stanza json_parser only parses one JSON level (nested objects remain strings), and ClickHouse nested attr serialization gotcha.
