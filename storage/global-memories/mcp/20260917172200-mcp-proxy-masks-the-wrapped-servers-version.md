---
date: 2026-09-17
keywords: ["mcp", "mcp-proxy", "serverInfo version", "diagnostics"]
trigger-on: ["mcp-proxy", "mcp-server-version-mismatch"]
---

## mcp-proxy advertises its own version, not the wrapped server's

`mcp_proxy/proxy_server.py` builds its gateway as `server.Server(name=response.serverInfo.name)` — passing **only the name** — so the version the proxied endpoint advertises is mcp-proxy's own MCP SDK version, never the wrapped server's. Observed: a `codebase-memory-mcp` image pinned to `0.10.8` advertised **`1.30.0`** (the installed `mcp` Python package version), which read as an engine/host version mismatch and sent a debugging session down a blind alley — the engine was 0.10.8 on both sides all along. `serverInfo.version` from a bridged server is therefore worthless for diagnostics: read the wrapped binary directly (`<bin> --version`, or the daemon's own `msg=daemon.start version=…` log line) and the pinned spec in the Dockerfile. Corollary: mcp-proxy forwards the *remote's* capability set, so a bridged `serverInfo`/`capabilities` pair is a hybrid — trust neither field without checking what the wrapped server itself reports.
