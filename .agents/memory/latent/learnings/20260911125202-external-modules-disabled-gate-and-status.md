---
date: 2026-09-11
keywords: ["external-modules", "disabled-umbrella", "module-list", "prune", "audit-03"]
---

# External-module state is per-module; a disabled umbrella is skipped entirely

## Disabled umbrella → skipped, not mirrored

`src/tools/external-modules/init.sh::_process_agentic_module` returns early for a disabled umbrella module, so its declared external modules get **no clone, no storage mirror, no wiring**. The config-only pass also refuses them (`_is_declared_by_any_module`). `commands/audit.md` §9 had claimed "cloned + mirrored but intentionally not wired" — the code is the source of truth, and the doc was corrected to the skip-everything design (audit-03 §9).

## Prune must not drop a name an enabled umbrella declares

`bin/init.sh::_prune_orphaned_external_modules` removes mirrors for names declared ONLY by a disabled umbrella. The guard is `_module_declared_names disabled` minus `_module_declared_names enabled` — without it, a name declared by both an enabled and a disabled umbrella is deleted even though the enabled module needs it.

## `devbot module list` status is per-module

The status is ✔ only when the module's **source resolves AND its storage mirror exists** — never the shared vendor clone. Several modules can share one repo (mindrally-*), so clone-presence falsely marked un-mirrored modules resolved (audit-03 §9).

## Wiring path is `.agents/`, not `.opencode/`

External modules wire into the project's devbot dir: `.agents/<type>/<name>`. Docs claiming `.opencode/<type>/<name>` are drift — the harness delegates from `.agents/`.
