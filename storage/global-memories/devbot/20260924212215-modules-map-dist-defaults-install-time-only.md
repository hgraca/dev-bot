---
date: 2026-09-24
keywords: ["devbot", "modules", "dist config", "reconcile"]
trigger-on: ["devbot-module-default", "modules-map"]
---

## A dist `modules` default reaches fresh installs only — existing ones keep the module enabled

`reconcile_global_config.py` merges the shipped `.devbot.global.dist.jsonc` into the runtime `.devbot.global.jsonc` only for top-level scalar keys and the `external_modules` catalogue (`MERGE_MAPS`); every other nested object is OPAQUE, and its own test asserts "a differing modules map is not reconciled". Combined with `_devbot_get_disabled_modules` treating an ABSENT key as ENABLED, adding `"<module>": false` to the dist map disables that module on freshly-installed machines only — an existing install keeps it enabled until the key is added to the runtime config by hand. Observed in the wild: the dist ships `"atlassian": false`, yet a machine's runtime `.devbot.global.jsonc` has no `atlassian` key at all, so atlassian is enabled there. When shipping a new module off by default, the dist line is necessary but NOT sufficient — the module should also gate itself, or the runtime key must be added deliberately.
