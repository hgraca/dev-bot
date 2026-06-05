---
date: 2026-04-19
keywords: ["ogham", "mcp"]
---

## Ogham MCP server disconnects after `uv tool upgrade`

After upgrading ogham-mcp via `uv tool upgrade`, the running MCP server connection becomes stale because the binary changed. All ogham MCP tool calls return "Not connected". The opencode session must be restarted (or the ogham MCP server restarted) for the upgraded version to be picked up.
