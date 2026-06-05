---
date: 2026-04-17
keywords: ["mcp"]
---

## M-FLOW-021: MCP git tool reliability issues

Developer agent attempting to stage and commit files using MCP git tools
MCP git tools can silently fail. When git operations don't work as expected, fall back to bash commands for git add and git commit
