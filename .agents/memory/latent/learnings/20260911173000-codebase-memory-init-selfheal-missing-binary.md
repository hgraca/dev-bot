---
date: 2026-09-11
keywords: ["codebase-memory", "mcp", "init", "reinit"]
---

# codebase-memory MCP needs an init.sh or reinit cannot self-heal a missing binary

The codebase-memory MCP server is registered in `opencode.jsonc` from the canonical `mcp.json`, which launches `bash -c "... exec codebase-memory-mcp ..."`. When the `codebase-memory-mcp` npm binary is not installed, the server dies at launch and the only trace is `.agents/logs/codebase-memory-mcp.log`: `bash: line 1: exec: codebase-memory-mcp: not found`. The failure is near-invisible because the module's session-start hook `tools/index-project.sh:44` does `command -v codebase-memory-mcp || exit 0` (fail-open by design), so `.agents/logs/hooks.log` reports `codebase-memory-index-project ok (no output)` — a genuine no-op, not a false success.

It could not self-heal because `devbot init`/`reinit` run each module's `init.sh` (via `bin/init.sh` `_run_module_script`) but the module shipped none, and `devbot update` — which runs `update.sh`, itself self-healing — is not part of the reinit path. Fix (commit `5de93ff3`): `src/agentic/codebase-memory/init.sh` delegates to the module's idempotent `install.sh` when the binary is absent. General rule for dev-bot engine modules: a module whose engine is a globally-installed CLI needs an `init.sh` dependency self-heal, because `devbot reinit` runs only `reset.sh` + `init.sh`. Installing the binary once and restarting opencode is still required for the server to come up (MCP servers load at startup; no hot-reload).
