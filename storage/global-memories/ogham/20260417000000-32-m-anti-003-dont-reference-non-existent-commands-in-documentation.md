---
date: 2026-04-17
keywords: ["ogham", "mcp"]
---

## M-ANTI-003: Don't reference non-existent commands in documentation

ogham hooks commands were aspirational but referenced in 15+ files
Verify commands exist before documenting them. Use actual MCP tool names, not planned CLI commands. Keep docs synchronized with implementation
