---
date: 2026-08-06
keywords: ["shell", "devbot", "_run_module_script", "refactoring"]
see: ["ADRs/20260806131001-harnesses-directory.md"]
---

## Generic `_run_module_script` pattern eliminates duplicated module lifecycle loops

Refactored 6 bin scripts (install, update, init, uninstall, reinit, up) to use a single generic function `_run_module_script(base_dir, script_name, label, ok_label, [args...])` in `src/_shared/functions.sh`. Thin wrappers (`_install_modules`, `_update_modules`, `_init_modules`, `_uninstall_modules`) provide action-specific naming. Also added `_collect_module_scripts` for script discovery. Eliminated ~200 lines of near-identical per-type loop boilerplate (previously each script had separate `_*_tools()` and `_*_agentic_modules()` functions). All modules types get the same disabled-module filtering, timing, and error handling. 16 new BATS tests cover the generic function.
