---
date: 2026-09-08
keywords: ["devbot", "mcp", "manifest", "architecture", "harness"]
see: ["ADRs/20260822115731-manifest-driven-hooks-architecture.md", "ADRs/20260822224308-harness-agnostic-module-init.md"]
---

## MCP servers are manifest-driven: one canonical mcp.json per module + a shared translator

MCP registration followed the pre-hooks pattern the hooks manifest ADR replaced: every module shipped **two** harness-shaped manifests (`mcp.opencode.json` `{key: {type: local|remote, …}}` and `mcp.claudecode.json` `{mcpServers: {key: {type: stdio|http, …}}}`) and each harness read its own file. The pair drifted in the wild — signoz's claudecode file pointed at `.opencode/signoz-mcp-server`, qmd/mdctx env vars existed only on the opencode side, react/svelte/signoz disagreed on `enabled` between harnesses.

Consolidation (13 modules): each module now declares its servers **once** in a canonical, harness-agnostic `src/agentic/<module>/mcp.json` (`{"mcp": {<server>: {type: stdio|http, command|url, env}}}`), and **one shared translator** (`src/_shared/mcp_translate.py`) maps it to each harness shape — opencode (`stdio→local`/`environment`, `http→remote`) and claudecode (`command`+`args`/`env`, `http→http`). Both harness inits, `reset.sh` stale detection (`mcp_key_is_current.py`) and `devbot list mcps` consume the translator; no consumer re-implements the mapping.

**Module gate policy**: no per-server `enabled` field and no per-harness enablement — module enablement is the only gate. An enabled module's servers are wired into every harness; a disabled module's servers are absent from every harness config (opencode reset prunes, claudecode regenerates).

**Divergence is expressed with tokens, not per-harness keys**: `{harness-dir}` (`.opencode`/`.claude`), `{host}` (opencode/`claude` — the product name, for codebase-index's `--host`), and existing placeholders `__GPU_ENABLED__`/`__DEV_BOT_ROOT__` resolved at registration by both harnesses. `{env:VAR}` is an env indirection resolved per target capability: opencode keeps the literal (native interpolation at launch); claudecode resolves at registration (`.mcp.json` cannot interpolate), omitting the env key with a WARN when unset.

**Approved behavior changes** beyond faithful translation: react/svelte/signoz now wire on claudecode (module-gate policy; their old claudecode `enabled:false` was per-harness enablement); signoz gained real claudecode provisioning (init.sh symlinks the binary per enabled harness — its old claudecode manifest was dead: disabled, wrong path, no `.claude/` binary); qmd/mdctx env is now single-source and reaches claudecode too; mdctx/codebase-memory opencode commands gained the log-redirect wrapper form used by every other stdio module.

**Exceptions staying structural**: codebase-index's opencode integration is plugin-based (`plugin.opencode.json`) — the opencode registration adapter skips plugin-declared modules so the server is not double-loaded; its canonical manifest serves claudecode. Dynamic runtime manifests (`.opencode/*.mcp.json`, `.claude/*.mcp.json`, e.g. jetbrains' runtime port) stay harness-native. `.gitignore` `mcp.json` corrected to `.mcp.json` (the rule was missing the dot — it hid module manifests while claudecode's regenerated `.mcp.json` went unprotected).

Rule for future MCP work: declare servers once in the module's canonical `mcp.json` and let the shared translator + harness inits wire them — never write a per-harness MCP manifest. Schema, tokens and per-harness wiring documented in `docs/mcp-config.md`.
