---
date: 2026-09-28
keywords: ["mcp", "uvx", "uv-tool", "startup-timeout", "stdio"]
trigger-on: ["mcp-stdio-launch", "uvx-per-invocation-resolution"]
---

## Launching a stdio MCP server with `uvx` re-resolves its dependencies on every start

`uvx <pkg>` builds an ephemeral environment and re-resolves the package's dependency graph against PyPI on **every** invocation, so an MCP server launched that way pays a network round-trip (tens of packages) on each start. When the index is slow or blackholed, uv's default 30 s read timeout can consume the entire budget of an MCP client's `initialize` handshake — the client reports `Operation timed out after 30000ms` and the server never answers. The failure is easy to misdiagnose because uv draws progress **only on a TTY**: spawned with pipes (as every MCP client does) it writes nothing, so the launcher's stderr log stays empty and the timeout looks like a dead server. Fix: install the tool once (`uv tool install <pkg>==<version>`) during setup and `exec` the installed executable at launch, so startup performs no network I/O (measured: cold uvx resolve 56 s, installed tool `initialize` ~3–5 s). Keep the version pin at install time and document that a manual `uv tool upgrade` drifts until the next install/update.
