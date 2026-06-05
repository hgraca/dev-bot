---
date: 2026-06-14
keywords: ["devbot", "mcp", "chrome-devtools", "mcp.opencode.json"]
---

## chrome-devtools MCP Config Missing `enabled` Key

`src/agentic/chrome-devtools/mcp.opencode.json` is the only MCP config file that lacks an `"enabled"` key. All other 6 modules with MCP configs include `"enabled": true` (graphify, codebase-index, playwright, websearch, context7, qmd). This is a minor inconsistency — it works because `bin/init.sh` doesn't require the key, but it creates an asymmetry in the pattern.
