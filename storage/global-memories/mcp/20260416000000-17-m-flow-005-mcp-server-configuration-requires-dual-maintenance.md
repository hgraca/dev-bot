---
date: 2026-04-16
keywords: ["mcp", "server"]
---

## M-FLOW-005: MCP server configuration requires dual maintenance

DevBot maintains MCP configs in both storage/opencode.jsonc and per-app installer templates
When fixing MCP server commands, update both the runtime config and the installer template to prevent drift between fresh installs and existing setups
