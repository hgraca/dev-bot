---
date: 2026-06-15
keywords: ["devbot", "functions", "duplication", "module-iteration", "refactor"]
---

# Duplicated module iteration + disabled-filtering pattern across init.sh and functions.sh

Both `src/agentic/external-modules/init.sh` (`_build_allowed_names`, line 68) and `src/_shared/functions.sh` (`_run_module_prereqs`, line 297) independently iterate `src/agentic/*/`, fetch disabled modules via `_devbot_get_disabled_modules`, and filter by module name with `grep -Fxq`. No shared helper exists to return the list of enabled module directory paths. A `_devbot_get_enabled_module_dirs` function in `_shared/functions.sh` would eliminate the duplication and prevent future callers from re-inventing the same pattern.
