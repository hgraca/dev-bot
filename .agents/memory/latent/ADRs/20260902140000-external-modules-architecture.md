---
date: 2026-09-02
keywords: ["external-modules", "devbot", "architecture", "provenance", "merge"]
see: ["PDRs/20260902140000-external-modules-full-intent.md"]
---

## External module architecture: path sources, namespacing, recursion, provenance

dev-bot's external-modules machinery (module at `src/tools/external-modules/`, config editor `src/_shared/merge_modules_jsonc.py`) was reworked over 2026-09-02 into a namespaced, recursive graph model. Key architectural decisions, all tested:

1. **Config field is `path`** (hard-renamed from the half-built `local_path`); url XOR path, path wins when both set, path entries are never cloned and their source is never modified (README cleanup only runs post-clone).
2. **Namespaced identity**: config keys are `<org>/<repo>` (git) or `local/<folder>`; `.agents` links nest at `.agents/<type>/<org>/<repo>`; storage mirrors sanitize `/` → `__` (`_external_storage_dir_name` in `src/_shared/functions.sh`) because each `storage/external-agentic-modules/<dir>` is a single-segment runnable module base.
3. **Wire every surviving config entry** in init.sh (declared + config-only url/path alike); user git adds register via CLI and wire on next init.
4. **Transitive declarations**: any external root's `external-modules.json` is merged (owner = module name) by install.sh in BFS rounds until closure (round cap 50, add-only inserts terminate cycles).
5. **Provenance**: merge insert/update with `--owner <mod>` records `_declared_by` (union); ownerless inserts (CLI) record `_user_added`. Prune removes an entry iff not user-added AND every declarer is disabled or gone (alive = enabled internal decl-carrying modules ∪ configured keys); markerless legacy entries prune only when declared solely by a disabled module (react/svelte disabled decls kept short-keyed — they share one repo url and cannot be renamed to org/repo without collisions).
6. **Merge script**: comment-preserving `--remove`/`--update` modes; remove/update rewrite the section canonically from the parsed object (comments inside `external_modules` are lost by design); the section finder is depth-aware and layout-independent (single-line configs, comments before the section).
7. install.sh/init.sh honor pre-set `DEV_BOT_ROOT`/`CONFIG_FILE`/`MODULES_DIR` for sandboxed BATS; `_devbot_get_disabled_modules` derives its reader from its own file location, not `DEV_BOT_ROOT`.

See: PDRs/20260902140000-external-modules-full-intent.md
