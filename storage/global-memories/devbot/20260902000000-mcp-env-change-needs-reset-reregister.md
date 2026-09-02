---
date: 2026-09-02
keywords: ["devbot", "mcp", "reset.sh", "reinit", "registration"]
trigger-on: ["mcp-env-reach-existing", "reset-reregister-mcp"]
---

## MCP env/config changes only reach fresh registrations — reset.sh must drop the module's MCP key first

Both `bin/init.sh::_register_module_mcp` (SKIP_EXISTS) and the harness's
`_write_opencode_config` (skip-if-exists) are idempotent-skip by design, and
harness `reset.sh` historically removed only the `devbot-tools` MCP key. So a
change to a module's MCP template env (e.g. qmd gaining
QMD_EXPAND_CONTEXT_SIZE, or QMD_LLAMA_GPU boolean → placeholder) NEVER reaches
an existing project's runtime opencode.jsonc after `devbot update` + `reinit` —
the stale entry (old env, crashing config) survives. Fix: reset.sh must drop
every module-managed MCP key whose template may have changed (loop over
`devbot-tools qmd` at minimum) so reinit re-registers it fresh. This exposed a
second latent bug: `remove_mcp_key.py` only handled the `.mcp.json`
"mcpServers" shape, so removals from opencode.jsonc (top-level "mcp" map) were
silent no-ops — the remover must handle whichever shape is present
(`data.get("mcp") or data.get("mcpServers")`).
