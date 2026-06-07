---
date: 2026-06-15
keywords: ["devbot", "opencode", "plugin", "hook", "symlink"]
---

## OpenCode hook registration centralized in _link_plugins()

Hook wiring was a brittle two-step process: symlink created by `src/tools/opencode/init.sh` `_link_plugins()`, JSONC registration done separately by each module's `init.sh` via `_upsert_opencode_plugin`. Missing either step caused silent hook failure. Consolidated both into `_link_plugins()` — it now auto-discovers hooks under `hooks/opencode/`, symlinks them, AND registers them in `opencode.jsonc`. This made 7 module `init.sh` files empty (removed) and 15 redundant `_upsert_opencode_plugin` calls across 10 modules (removed). Module lifecycle scripts that only checked system tool presence with no actual install/update steps were also deleted (20 files total). All lifecycle runners guard against missing scripts with `[[ -f ]]` checks.
