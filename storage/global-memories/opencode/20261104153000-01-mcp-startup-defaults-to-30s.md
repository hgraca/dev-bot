---
date: 2026-11-04
keywords: ["opencode", "mcp", "timeout", "status=failed"]
trigger-on: ["mcp-server-startup", "container-backed-mcp"]
---

## MCP startup defaults to 30 s, and a slow server reads as `failed`

opencode allows an MCP server 30 000 ms to connect and fetch tools (`mcp.<server>.timeout`, default 30 s; it also applies to tool calls). A server that launches a container — image pull, JVM/container boot, background sync — can exceed that on a cold start. The harness then logs `message="server unavailable" key=<server> type=local status=failed` in `~/.local/share/opencode/log/opencode.log` and exposes no tools; the config still says `enabled: true`, so it looks like the enable failed rather than the server being slow.

Diagnose before changing config: run the server's launcher by hand and speak JSON-RPC to it on stdin (`{"jsonrpc":"2.0","id":1,"method":"initialize",...}` then `tools/list`), timing each reply. If `initialize` answers but late, the problem is startup latency, not auth or a broken command. Measured on a SonarQube container: 13-15 s container/JVM boot plus 15 s of backend API calls = 29-46 s, right at or past the default.

Fix by raising `timeout` on that server (e.g. `120000`) and restarting the harness — opencode reads its config once at startup. If the module ships the manifest, carry `timeout` through the translator rather than hand-editing each project's config.
