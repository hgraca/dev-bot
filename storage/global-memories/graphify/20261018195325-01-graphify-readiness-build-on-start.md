---
date: 2026-10-18
keywords: ["graphify", "not_ready", "graph-mcp", "worktree", "hot-reload"]
aliases: ["graphify readiness", "empty placeholder graph", "graphify building"]
trigger-on: ["graphify-mcp-readiness"]
---

## Graphify readiness: build on MCP start and answer `not_ready`

Graphify's MCP server loads `graphify-out/graph.json` at startup but hot-reloads it on every tool handler when the file's mtime/size changes, so a background build can become visible without restarting the server. The trap is the empty placeholder graph: it exists only so the server can start, but without a readiness gate the tools return zero-node results that look like "no match". The fix is to start `graphify update .` from the MCP wrapper on launch, wrap the CallToolRequest handler, and answer `graphify: not_ready (building|disabled|failed|empty) — <reason>` until the graph has nodes; `disabled` means `.graphifyignore` turned indexing off, `failed` points at `graphify-out/.graphify-update.log`, and `building` is retryable. A linked worktree can be seeded from the main checkout first because graph nodes store `source_file` as a project-relative path (no absolute paths); the background update then refreshes it for the worktree branch. Do not wait for the graph before launching the server (that deadlocks the build-on-start flow), and do not rely on git hooks for freshness: MCP start plus the session-created update is enough. The background updater must `cd` into the project path, or it builds whatever checkout happened to be the caller's cwd.
