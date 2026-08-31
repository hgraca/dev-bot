---
date: 2026-08-06
keywords: ["signoz", "clickhouse", "nested-attributes", "json"]
trigger-on: ["nested-attribute-json", "clickhouse-attribute-map"]
---

## SigNoz ClickHouse stores nested OTel attribute maps as JSON strings

When the OTel collector exports a log/span with a nested map attribute value (e.g. `attributes["context"] = KeyValueList{...}`), SigNoz ClickHouse serializes the entire map to a JSON string on storage. The SigNoz API returns it in `attributes_string` as a string, not as individual sub-attributes. This means nested attribute structures are NOT individually searchable/filterable in SigNoz. Always flatten nested maps to top-level attributes before OTLP export — use filelog `parse_to: attributes` (flat), never `parse_to: attributes.<key>` (nested). For deeply nested JSON in log bodies, chain multiple `json_parser` operators each emitting flat to `attributes`.
