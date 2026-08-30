---
date: 2026-08-22
keywords: ["devbot", "opencode", "config", "reconcile"]
---

# dev-bot's opencode.jsonc drifts from the dist; heal via targeted _reconcile_* steps

dev-bot's `opencode.jsonc` is managed by `_write_opencode_config` (copies the dist, skips if the file already exists) plus `_upsert_opencode_plugin` (adds plugin entries, never removes). Net effect: the runtime config never loses stale entries and never gains new dist entries, so it drifts after refactors — e.g. the hook consolidation left ~12 stale `watcher.ignore` plugin entries, and older projects lacked the `/tmp/*` `external_directory` allow (so `/tmp/opencode` writes were flagged). Fix pattern: `_reconcile_watcher_ignore` and `_reconcile_external_directory` in `src/harnesses/opencode/init.sh` — targeted, surgical, idempotent steps that heal a specific drift on each init, rather than full regeneration (which would clobber the user's local overrides like model or allow-lists). When refactoring anything that touches `opencode.jsonc`, add a `_reconcile_*` step for the field you changed.
