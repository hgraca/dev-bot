---
date: 2026-04-17
keywords: ["mcp", "server"]
---

## M-ARCH-011: Environment variable injection for MCP path resolution

MCP server wrappers need access to DevBot installation paths
Use MCP config environment block with {file:storage/secrets/path} pattern instead of runtime path computation. More reliable across different shell environments and symlink scenarios.
