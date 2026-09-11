---
date: 2026-09-11
keywords: ["devbot", "mcp", "env-var", "gate", "manifest"]
---

# dev-bot's `{env:VAR}` launch gate must also scan dynamic runtime manifests

## What the gate is

`_devbot_missing_mcp_env_vars` (`src/_shared/functions.sh`) collects `{env:VAR}` references whose variable is unset/empty, using `src/_shared/mcp_env_refs.py` to parse manifests. `devbot init`/`reinit` present a notice; the harness `start.sh` scripts use mode `gate` to abort (interactive) or warn (non-interactive). It exists because OpenCode resolves `{env:VAR}` at launch and silently substitutes an empty string when unset.

## The trap

The collector originally scanned only **canonical** module manifests (`src/{tools,agentic,harnesses}/*/mcp.json`, shape `{"mcp": {<server>: {...}}}`, reading the `env` map). Modules that write a **dynamic runtime manifest** instead — e.g. jetbrains' `<project>/.opencode/jetbrains.mcp.json`, shape `{<server>: {...}}` with no `mcp` wrapper and indirection under `headers` — were invisible to the gate. Jetbrains' `IJ_MCP_SERVER_PROJECT_PATH` header therefore could reference `{env:JETBRAINS_PROJECT_PATH}` unset at launch and silently become an empty header.

## The fix (2026-09-11)

- `mcp_env_refs.py::env_refs` is now shape-aware: top-level `{"mcp": {...}}` → canonical (reads `env`); otherwise top-level `{<server>: {...}}` → runtime (reads `env`/`environment`/`headers`).
- `_devbot_missing_mcp_env_vars` also loops `<project>/.opencode/*.mcp.json`, labels each ref by manifest basename, and honours the disabled-module skip (same as the canonical loop).

Rule for future module work: if an init writes a dynamic `.opencode/<name>.mcp.json` carrying `{env:VAR}`, the gate now covers it — but the manifest must keep a top-level `{<server>: {...}}` shape and put the token where the parser looks (`env`, `environment`, or `headers`).
