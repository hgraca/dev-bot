---
date: 2026-11-09
keywords: ["opencode", "mcp", "mcp list", "runtime enablement", "enabled"]
---

## `opencode mcp list` reports the config file, not the running session

`opencode mcp list` reads the merged config, so a server can print `disabled` while the live session has it enabled — opencode toggles MCP servers at runtime without rewriting `opencode.jsonc`. Treating that output as proof the tools are unavailable is wrong: in this session `atlassian` showed `disabled` (the project config still had `"enabled": false`) while `atlassian_*` tools were callable and `list_mcp_resources` named the server as connected. Check the actual toolset or `list_mcp_resources` before telling the human a server is off, and never ask for a restart on the strength of `mcp list` alone — the file and the session disagree, and the session is what answers.
