---
date: 2026-04-18
keywords: ["mcp"]
---

## M-FLOW-022: Git MCP tool reliability issues require bash fallback

Multiple sessions where developer agent attempted to use git MCP tools for staging and committing
The git MCP tools frequently return empty results or silently fail to actually perform git operations. Always verify git status after MCP calls and fall back to bash commands when operations don't complete.
