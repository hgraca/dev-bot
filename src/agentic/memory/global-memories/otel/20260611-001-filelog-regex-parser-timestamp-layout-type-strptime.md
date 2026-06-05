---
date: 2026-06-11
keywords: ["otel", "filelog", "regex_parser", "timestamp", "strptime"]
---

## filelog regex_parser timestamp requires `layout_type: strptime` for %Y/%m patterns

The OpenTelemetry Collector's `filelog` receiver `regex_parser` operator uses Go time layouts by default in its `timestamp.layout` field. If you supply strptime-style tokens like `%Y`, `%m`, `%d`, `%H`, `%M`, `%S`, `%L` — which match CRI log format timestamps (`2026-06-11T10:30:00.123Z`) — you must also set `layout_type: strptime` on the `timestamp` block. Without it, the parser silently fails and logs receive the collection timestamp instead of the actual log timestamp. The parameter goes between `parse_from` and `layout` in the `timestamp:` block: `parse_from`, `layout_type: strptime`, `layout: '%Y-%m-%dT%H:%M:%S.%LZ'`.
