---
date: 2026-06-15
keywords: ["devbot", "external-modules", "init", "wiring", "disabled_modules", "symlink"]
see: ["project/20260614150000-two-phase-install-gap.md", "project/20260615091800-external-module-lifecycle-encapsulation.md"]
---

# Init wiring symlinks external modules from disabled internal modules

When an internal module (e.g., `svelte`) is added to `disabled_modules`, `bin/init.sh` correctly skips `svelte/init.sh`, but `_wire_external_modules` still symlinks the external modules declared by svelte (`mindrally-svelte`, `sveltekit-structure`, `svelte5-best-practices`). Root cause: the wiring step reads `.devbot.jsonc modules` verbatim with zero `disabled_modules` awareness, while `merge_modules_jsonc.py` is add-only and never removes stale entries from disabled modules. Fix: `external-modules/init.sh` now builds an allowed-names set by scanning `src/agentic/*/external-modules.json` for enabled modules only, and skips symlinks and storage setup for entries not in that set. Both Phase 1 (symlink loop) and Phase 2 (storage setup) are filtered. `merge_modules_jsonc.py` remains add-only, but `external-modules/install.sh` rebuild should also be made destructive as a follow-up.
