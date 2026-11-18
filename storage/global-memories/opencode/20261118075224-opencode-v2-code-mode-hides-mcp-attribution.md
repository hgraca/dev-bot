---
date: 2026-11-18
keywords: ["opencode", "code-mode", "mcp", "stats", "session_message"]
---

## opencode-v2 code mode hides MCP calls from the session database

Under opencode 2.x code mode the model reaches MCP tools through the `execute` tool, and `session_message` records only `execute` — no per-server tool name. So `stats`/`grade-tools` cannot attribute MCP usage for those sessions. Direct (non-code-mode) MCP calls are recorded as `<server>_<tool>` and can be classified against the servers each project's `opencode.jsonc` declares (`mcp.servers` in v2, a v1-shaped `mcp` map, or `.opencode/*.mcp.json`). Two traps: an empty MCP table on a v2 session is missing attribution, not proof of disuse; and an exact name match must not be classified — v2 ships native tools whose name equals a server's (`websearch`), so counting those invents usage. Implemented in `src/harnesses/opencode-v2/stats.py` (audit-02 F-2): classify `<server>_<tool>`, skip exact matches, and say so in `devbot:stats` instead of hardcoding `mcp_servers: []`.
