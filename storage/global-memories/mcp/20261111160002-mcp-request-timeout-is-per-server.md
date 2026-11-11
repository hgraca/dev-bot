---
date: 2026-11-11
keywords: ["mcp", "timeout", "opencode", "datasources"]
trigger-on: ["mcp-client-timeout"]
---

## MCP request timeout is per server, and a long tool call needs it raised

The MCP client gives each server a request timeout; opencode's default is 30 s for connecting, fetching tools **and** tool calls. A heavy `execute_sql` over a large table exceeds it and the call fails with JSON-RPC `-32001 Request timed out` — not a database error, so it reads like a broken connection. Raise it per server with `timeout` (milliseconds) in the server config: dev-bot datasources read `mcp_timeout_ms` per datasource from `.devbot.global.jsonc` (default 60 s) and write it into the generated opencode manifest. A change needs `devbot reinit` plus a harness restart, because the dynamic server entry is merged into `opencode.jsonc` at init. Claude Code has no per-server equivalent — it reads the `MCP_TIMEOUT` environment variable instead.
