---
date: 2026-06-18
keywords: ["signoz", "create-dashboard", "mcp", "api"]
---

## signoz_create_dashboard MCP tool creates dashboards with full widget JSON

The `signoz_create_dashboard` MCP tool accepts `title`, `layout`, `widgets`, `variables`, `tags`, and `description` parameters to create complete dashboards programmatically. Widget JSON can be copied verbatim from existing dashboards (via `signoz_get_dashboard`). The tool returns the created dashboard UUID. Local JSON files should store the `data` field from the API response for import/recreation. Unlike `signoz_update_dashboard` which expects the `data` contents directly, `signoz_create_dashboard` accepts individual parameters.
