---
date: 2026-11-21
keywords: ["graphify", "mcp", "request_handlers", "uv-tool", "version-pin"]
---

## graphify's serve shim needs mcp 1.x; an unpinned `--with mcp` breaks it

`graphify-serve-shim.py` wraps the upstream `CallToolRequest` handler through `Server.request_handlers`, which **mcp 2.x removed**. The module installed its tool as `uv tool install graphifyy --with mcp`; with mcp unpinned a fresh install picked 2.x and the MCP server died at launch with `AttributeError: 'Server' object has no attribute 'request_handlers'` — the capability was simply absent for the whole session, visible only as `mcp connect failed … exited with code 1` plus a traceback in `graphify-mcp.log`. graphify itself tolerates 2.x (its own source handles the `AnyUrl` removal), so the constraint is the shim's. Pin `--with "mcp<2"`, matching the gateway images, and treat an existing tool on 2.x as needing repair (`--force`) — the "already installed" skip otherwise keeps the broken one forever.
