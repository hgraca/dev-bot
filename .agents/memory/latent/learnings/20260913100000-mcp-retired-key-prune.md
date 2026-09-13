---
date: 2026-09-13
keywords: ["mcp", "reset", "reinit", "devbot"]
---

# Removing a module's MCP server needs an explicit retired-key prune

`src/harnesses/opencode/reset.sh` prunes MCP keys through two paths, and both
are keyed on the module's **canonical `mcp.json`**:

- the stale-refresh list (`REFRESH_MODULES`) — `[[ -f "${local_tpl}" ]] || continue`;
- the disabled-module prune — `if [[ -f "${mod_dir}/mcp.json" ]]`.

So when a module **removes** its `mcp.json` entirely (qmd's MCP server was
retired in commit `797c8300`), neither path can discover the key, and an
existing install keeps the dead server in `opencode.jsonc` forever — reinit
never self-heals it, because merge is skip-if-exists and reset's prunes can't
see the key. Fix: an explicit `RETIRED_MCP_KEYS` list in reset.sh that
unconditionally removes the key when present. claudecode is unaffected — it
regenerates `.mcp.json` from scratch each reinit.

Rule for future MCP-server removals: delete the module's `mcp.json` **and** add
the key to `RETIRED_MCP_KEYS` in the opencode reset, or existing configs keep a
dead server. (The mcp.json.future "preserve for later" variant was tried and
dropped — a retired server is retired.)
