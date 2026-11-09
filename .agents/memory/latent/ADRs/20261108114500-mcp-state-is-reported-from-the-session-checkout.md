---
date: 2026-11-08
keywords: ["mcp", "project-for-path", "session-root", "module-gate"]
aliases: ["is the MCP enabled", "mcp configured vs live", "session checkout config"]
---

## `project-for-path` reports configured MCP state from the session checkout

MCP wiring belongs to the checkout the harness runs in, not to the project that owns an arbitrary
file: a monorepo workspace reads its own `opencode.jsonc`, while a child project may carry a
different (or no) generated config. `project-for-path` therefore resolves `mcps` from the nearest
generated config above the owner and accepts `--session-root <dir>` (or `DEV_BOT_PROJECT_ROOT`) to
name the live checkout outright — a session root is never walked, so a parent workspace's config
cannot leak in. Both harness shapes are read, opencode's `mcp` map authoritative per server and a
`.mcp.json` entry only adding servers, because Claude Code has no per-server switch; `mcps_sources`
names the files consulted and `mcps_errors` reports a config that could not be read, parsed, or
shaped. The reported `enabled` is configuration, not reachability — an enabled server can still be
offline or unauthenticated — so callers treat it as necessary and never as proof the tools will
answer. Module enablement stays a separate gate (`--key modules`, absence meaning enabled): both must
be on before a module's MCP is assumed usable.
