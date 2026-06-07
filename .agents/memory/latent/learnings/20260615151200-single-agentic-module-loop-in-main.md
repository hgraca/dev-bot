---
date: 2026-06-15
keywords: ["devbot", "external-modules", "init.sh", "refactor", "main-loop"]
see: ["project/20260615150400-build-allowed-names-replaced-with-single-python-call.md"]
---

# Single agentic-module loop in main() with per-module function calls

`src/agentic/external-modules/init.sh` restructured so that `main()` has one loop through `src/agentic/*/` and each iteration calls only `_process_agentic_module` — a function that delegates to `_is_disabled`, `_get_declared_names`, `_lookup_entry`, `_resolve_source_dir`, `_wire_one_module`, and `_setup_one_storage`. This eliminated `_build_allowed_names`, `ALLOWED_NAMES`, `_wire_symlinks`, and `_setup_storage` (all multi-entry-loop functions). Module entries from `.devbot.jsonc` are pre-read once into `MODULE_ENTRIES` as `name\x1furl\x1flocal_path\x1fpaths_json` per line for O(n) lookup per declared name. Commit: 9dd3c12.

Design principle: the `main()` loop contains only function calls, no direct logic (no conditionals, no variable assignments, no python invocations).
