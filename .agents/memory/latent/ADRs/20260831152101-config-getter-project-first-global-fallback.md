---
date: 2026-08-31
keywords: ["devbot", "config", "config-getter", "precedence"]
---

## Canonical config getter: _devbot_get_config (project-first, global-fallback)

DevBot scalar config reads now go through `_devbot_get_config <key> [project_dir]` in `src/_shared/functions.sh`: it reads `.devbot.project.jsonc` first and falls back to `.devbot.global.jsonc`, printing the raw value (empty when unset in both). An explicit project value wins — even `false` — because `read_jsonc.py` prints `false` as a non-empty string, so the global fallback only fires when the project value is truly absent. `_devbot_get_project_dir` and `_devbot_get_harness` were migrated to thin wrappers (keeping their `.agents` default and `opencode` validation); `_devbot_get_disabled_modules` was deliberately NOT migrated because it merges `modules` maps per-key, a shape a scalar getter cannot express. The `commit_memory` bug (read project-only, global value ignored) motivated this unification; regression coverage lives in `src/_shared/tests/config_tests.bats`.
