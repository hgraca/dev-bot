---
date: 2026-08-23
keywords: ["devbot", "disabled_modules", "global", "project", "union"]
trigger-on: ["devbot-disabled-modules", "module-enable"]
---

## disabled_modules is a union — a globally-disabled module can't be re-enabled per-project

SUPERSEDED by the `module_states` override-map design (see the `module-states-map-override` note in this folder). The old `disabled_modules` list was merged as a sorted unique union of global + project, so a globally-disabled module could not be re-enabled per-project. That's now fixed: `module_states` (map) lets the project value override the global value.
