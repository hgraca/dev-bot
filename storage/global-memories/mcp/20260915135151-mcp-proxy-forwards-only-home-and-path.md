---
date: 2026-09-15
keywords: ["mcp", "mcp-proxy", "environment", "docker", "stdio"]
trigger-on: ["mcp-stdio-http-bridge", "mcp-proxy"]
---

## mcp-proxy forwards only HOME and PATH unless --pass-environment is given

`mcp-proxy` (the Python package used to bridge a stdio MCP server to streamable-http) spawns the server with a **minimal** environment: only `HOME` and `PATH` are inherited. Every other variable from the container or parent process is dropped silently.

The failure is invisible at the transport layer: the proxy starts, the container is healthy, and an MCP `initialize` handshake succeeds — but the spawned server never saw its own configuration variables. A server configured entirely by env (e.g. `MDCTX_ROOT`/`MDCTX_INDEX`) then falls back to its defaults and operates on the wrong directory, failing only when a tool is actually called:

```
Could not load or build an index at /context-index.json for root /.
(EACCES: permission denied, scandir '/etc/ssl/private')
```

Fix: pass `--pass-environment` to `mcp-proxy`. Verify by inspecting the spawned child, not the proxy:

```sh
# inside the container — the child pid, not the proxy
tr '\0' '\n' < /proc/<child-pid>/environ | grep -E 'MY_VAR|HOME|PATH'
```

Adding `--pass-environment` is harmless when a server needs no extra vars, and it removes the dependence on the proxy's incidental `HOME` forwarding.
