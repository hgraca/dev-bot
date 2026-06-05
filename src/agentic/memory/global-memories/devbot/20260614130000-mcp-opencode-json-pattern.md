---
date: 2026-06-14
keywords: ["devbot", "mcp", "opencode", "mcp.opencode.json"]
---

## mcp.opencode.json Module Pattern

Each agentic module that provides an MCP server declares it in `src/agentic/<module>/mcp.opencode.json`. The file has exactly one top-level key (the MCP server name) and supports two transport types:

- **`"type": "local"`** with a `"command"` array (e.g. `["npx", "-y", "chrome-devtools-mcp@latest"]`)
- **`"type": "remote"`** with a `"url"` string (e.g. `"https://mcp.context7.com/mcp"`)

Optional keys: `"enabled"` (boolean, default missing in chrome-devtools), `"oauth"` (boolean, for remote servers), `"environment"` (object with env vars, used by qmd for `__GPU_ENABLED__` placeholder).

The `__GPU_ENABLED__` placeholder (used by qmd module) is substituted at registration time by `bin/init.sh` via string replacement before merging into the project's opencode config.

Seven modules currently have this file: graphify, codebase-index, playwright, chrome-devtools, websearch, context7, qmd. Registration is handled automatically by `_register_module_mcp_servers()` in `bin/init.sh`, which scans for all `src/agentic/*/mcp.opencode.json` files, reads the MCP key, and inserts them into the project's `opencode.jsonc` using `merge_mcp_jsonc.py` (comment-preserving) with a fallback to `read_jsonc.py` + `jq` for files without an existing mcp section.
