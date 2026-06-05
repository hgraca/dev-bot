---
date: 2026-04-23
keywords: ["ogham", "mcp"]
---

## M-ARCH-024: MCP server connections become stale after binary upgrades

After uv tool upgrade ogham-mcp, the running MCP server connection failed with 'Not connected' errors
MCP server connections are tied to specific binary versions. Session restart required after upgrading MCP server binaries to establish new connections
