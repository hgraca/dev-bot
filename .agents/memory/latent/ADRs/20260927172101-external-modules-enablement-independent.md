---
date: 2026-09-27
keywords: ["devbot", "external-modules", "enablement", "vendor", "storage"]
see: ["learnings/20260615102800-external-module-wiring-disabled-symlink-bug.md", "learnings/20260615091800-external-module-lifecycle-encapsulation.md"]
---

## External-module provisioning is independent of module enablement

The `external_modules` config store, the `vendor/` clones and the `storage/external-agentic-modules/` mirrors live under the global dev-bot root and are shared by every registered project, while the `modules` enablement map is per-project — so provisioning must never consult enablement. `_devbot_rebuild_external_module_config` (`src/_shared/functions.sh`, called by `src/tools/external-modules/install.sh` and `bin/up.sh`) merges every module's `external-modules.json` declarations, scanning both `src/agentic/*` and `src/tools/*`; all configured entries are cloned and mirrored. `bin/init.sh:_prune_orphaned_external_modules` removes a mirror only when no module declares its name (any state) **and** it is absent from the config. Enablement gates only per-project wiring — the `.agents/<type>/<name>` symlinks, an external's `init.sh` and its memory links (via `_devbot_disabled_external_names`). `devbot module remove` remains the only explicit delete and `vendor/` is never pruned.
