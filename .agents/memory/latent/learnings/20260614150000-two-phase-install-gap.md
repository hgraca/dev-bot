---
date: 2026-06-14
keywords: ["devbot", "install", "external-modules", "two-phase", "lifecycle"]
see: ["project/20260615091800-external-module-lifecycle-encapsulation.md"]
---

# Two-Phase Install Gap: External Modules Not Cloned on First Install

## The problem

`bin/install.sh` creates `.devbot.jsonc` by copying `.devbot.global.dist.jsonc`, which has **no `modules` key**. Then `_install_agentic_modules()` runs `src/agentic/external-modules/install.sh`, which reads `.devbot.jsonc modules` and finds **zero entries** — so no external repos are cloned into `vendor/` on first install.

The `modules` key only gets populated later by `bin/up.sh:_rebuild_external_module_config()`, which scans `src/agentic/*/external-modules.json` and merges declarations via `src/_shared/merge_modules_jsonc.py`.

This means `devbot install` is a **two-phase process**: (1) install creates config without modules, (2) up.sh populates modules, and only on a subsequent `devbot install` run does the cloning actually happen.

## Fix approach

Insert `_rebuild_external_module_config()` (or equivalent logic) into `bin/install.sh:main()` between `_setup_devbot_config()` and `_install_agentic_modules()` — this populates the `modules` key before the external-modules install script runs. The `_rebuild_external_module_config` function exists in `bin/up.sh` and can be extracted or referenced.

## Key files

- `bin/install.sh` — main install orchestrator
- `bin/up.sh:_rebuild_external_module_config()` — config population logic (lines 74–135)
- `src/agentic/external-modules/install.sh` — cloning logic (reads config)
- `src/_shared/merge_modules_jsonc.py` — comment-preserving JSONC merge
- `.devbot.global.dist.jsonc` — template without `modules` key
- `src/agentic/*/external-modules.json` — per-module declarations
