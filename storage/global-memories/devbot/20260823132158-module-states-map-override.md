---
date: 2026-08-23
keywords: ["devbot", "modules", "config", "enabled", "disabled", "external_modules"]
trigger-on: ["devbot-module-enable", "modules", "external_modules"]
---

## Module enable/disable is a modules map — project overrides global

Module enable/disable uses a `modules` map (module → bool, `false` = disabled) in `.devbot.global.jsonc` (global defaults) and `.devbot.project.jsonc` (project overrides). `_devbot_get_disabled_modules` computes the effective disabled set: the project value wins when present, else the global value, else enabled — so a project can re-enable a globally-disabled module (`"claudecode": true`) or disable an enabled one. `modules` also enables/disables _external_ modules (skipped during `external-modules/init.sh` wiring when disabled). External module config (url/paths) lives in a separate `external_modules` key. This replaced the old union-of-two-`disabled_modules`-lists pattern. The key was briefly `module_states` before settling on `modules` (with `modules`→`external_modules` for the external config).
