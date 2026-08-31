---
date: 2026-08-06
keywords: ["otel", "stanza", "json_parser", "filelog"]
trigger-on: ["json-parser-nested", "parse-to-attributes-nesting"]
---

## stanza json_parser with parse_to: attributes stores nested objects as Go maps, not strings

The filelog receiver's `json_parser` operator with `parse_to: attributes` only deserializes the FIRST level of JSON as flat key-value pairs. Nested JSON objects are stored as Go `map[string]interface{}` values in the stanza entry's attributes — NOT as serialized strings. For example, parsing `{"message":"hi","context":{"foo":"bar"}}` produces `attributes["message"] = "hi"` (string) and `attributes["context"] = map{"foo":"bar"}` (Go map). The JSON string representation seen in SigNoz happens downstream when ClickHouse serializes the nested map on store. Do NOT chain a second `json_parser` on the same attribute — it expects a string and silently fails on a map. Use an OTTL `merge_maps` in a transform processor instead to flatten the map into individual attributes.
