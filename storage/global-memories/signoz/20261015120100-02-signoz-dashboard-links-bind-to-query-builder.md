---
date: 2026-10-15
keywords: ["signoz", "dashboard", "context-link", "interactivity", "clickhouse"]
aliases: ["no context menu on dashboard panel", "table row link", "View in Traces"]
trigger-on: ["signoz-dashboard-row-link", "signoz-context-link"]
---

## SigNoz dashboard row links only bind on Query Builder panels

A dashboard Context Link builds its URL from `{{_field}}` placeholders that resolve against the clicked panel's **group-by fields**, which the backend only knows for Query Builder queries; on a raw ClickHouse SQL panel the placeholders never bind, and in the tested build (self-hosted v0.143.0) **no context menu appears on such a panel at all** — clicking a row does nothing, and neither `View in Traces` nor cross-filtering is offered, even though the docs list Context Links as a table-panel option (the config is accepted on save, so it looks valid). Verified working combination: a Builder-backed panel naming the field in its `selectFields`, plus a link object such as `{"name": "Open trace", "url": "/trace/{{_trace_id}}", "renderVariables": true}` — the link then renders directly on the panel, with no context menu involved. Consequence: when the data is only reachable via ClickHouse, it cannot carry a per-row link, so choose the panel by what it must link to rather than by how it should look.
