---
date: 2026-07-31
keywords: ["devbot", "mcp", "tools-mcp", "agentic-tools"]
---

## Remove `devbot agentic-tools` CLI subcommand — tools now exposed via `devbot-tools` MCP server

The `devbot agentic-tools` CLI subcommand (which listed available custom tools for agents) was removed from `bin/devbot` and all agent instructions. Custom tools (search-memories, git-report, tree, format-md, etc.) are now exposed to agents via the `devbot-tools` MCP server. Agents access them as `devbot-tools_*` in their tool palette without needing a separate discovery step.
