---
date: 2026-11-11
keywords: ["devbot", "harness", "reset", "prune", "destructive"]
aliases: ["_harness_selected", "unselected harness tree", "disabled set fallback"]
see: ["ADRs/20261111173202-harness-enablement-is-the-root-harness-key.md", "learnings/20260921120419-project-dir-swallow-silently-degrades-config.md"]
---

# Destructive cleanup must read the scalar `harness` key, not the disabled set

`_devbot_get_disabled_modules` is a _convenience_ set: its inline Python calls `json.loads` on the `modules` value, so a malformed map makes it print `[]` through its `|| echo "[]"` fallback. Read as "nothing is disabled", that means **both** harnesses look enabled — fine for writes, fatal for deletes.

Three paths had that shape after harness enablement moved to the scalar key: `src/agentic/codebase-index/reset.sh` (`_remove_configs` / `_remove_store` deleted both `.opencode` and `.claude` artifacts on every reinit) and `src/agentic/netsuite/init.sh` (`_netsuite_prune` removed stale `netsuite-*.mcp.json` from both trees). Switching harness could therefore destroy a tree dev-bot no longer manages, and a corrupt config could widen the blast radius to both.

## The rule

A cleanup/delete path gates on `[[ "$(_devbot_get_harness "${PROJECT_DIR}")" == "<harness>" ]]` — the scalar key has a documented default (`opencode`) and never returns empty, so a config that cannot be parsed still resolves to exactly one harness. The disabled set stays fine for "should this module run at all" and for deciding what to _write_, never for deciding what to _delete_.

`bin/init.sh` follows the same principle on the write side for the opencode config: `_resolve_opencode_config` returns nothing unless opencode is selected, so a leftover `opencode.jsonc` on a claudecode project is never registered into. Its `_register_module_mcp` already no-ops on an empty config path, so no caller needed changing.
