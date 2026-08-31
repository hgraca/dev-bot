---
date: 2026-04-19
keywords: ["mcp"]
---

## M-FLOW-035: Git MCP tools may return empty output requiring bash fallback

Reviewer agent trying to get git status and diff output
When git MCP tools return only repo path with no content, this indicates tool failure. Have fallback strategy or work with available information
