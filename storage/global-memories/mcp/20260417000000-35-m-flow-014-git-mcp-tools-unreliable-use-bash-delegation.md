---
date: 2026-04-17
keywords: ["mcp"]
---

## M-FLOW-014: Git MCP tools unreliable - use bash delegation

Git MCP tools returned empty results throughout session
When MCP tools fail silently, delegate git operations to task subagent with direct bash commands. More reliable than MCP for git workflows
