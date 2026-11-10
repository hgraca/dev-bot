---
date: 2026-11-10
keywords: ["opencode", "mcp", "runtime enablement", "mcp-sync"]
aliases: ["runtime mcp toggle", "mcp enabled flag sync"]
see: ["ADRs/20261108114500-mcp-state-is-reported-from-the-session-checkout.md"]
---

## MCP runtime enablement is written back to opencode.jsonc

opencode holds MCP enablement in memory: a harness toggle never rewrites the config, no state file or event carries it, `opencode mcp list` re-reads the config, and `opencode mcp debug <name>` reports auth and reachability rather than enablement. The only runtime source is the harness API `client.mcp.status()` (`connected | disabled | failed | needs_auth | needs_client_registration`), reachable in-process from a plugin. `mcp-sync` (`src/harnesses/opencode/hooks/mcp-sync.ts`) polls it every 2s and writes the implied flag into `<root>/opencode.jsonc` on transitions only — `connected` → true, `disabled` → false, `failed`/`needs_auth`/absent → no write — and the first poll seeds a baseline so startup states never rewrite anything. It edits by span, so comments and `{env:VAR}` tokens survive; it never copies the harness's resolved config, which can hold an interpolated secret, taking a global-only server's raw definition instead; it holds an ownership-token lock directory around read/revalidate/rename and retries a failed write on the next poll. The target is deliberately only `<root>/opencode.jsonc`, the file `project-for-path --key mcps` reads (`.opencode/` and `opencode.json` are never written). Consequence: the config stays the single source the gate reads, and the write takes effect on the next launch because opencode reads its config at startup.
