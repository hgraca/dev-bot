---
date: 2026-06-15
keywords: ["devbot", "opencode", "disabled_modules", "symlink", "dual-layer"]
---

## opencode tool init.sh created symlinks for disabled modules — dual-layer init requires duplicate disabled checks

`_link_modules()` in `src/tools/opencode/init.sh` looped all `src/agentic/*/` creating `.opencode/` symlinks (agents, commands, skills, tools, plugins) with zero `disabled_modules` check. This was the actual source of the graphify/svelte artifacts reported by the user — even after `bin/init.sh` was fixed to skip disabled modules in its own loop, the tools-layer symlink creation ran independently. dev-bot's init is dual-layer (bin/init.sh orchestrates module init + tools-layer opencode/init.sh creates project-level symlinks), and `disabled_modules` must be checked in BOTH layers. Fixed by adding disabled_modules parsing to `_link_modules()` (commit 6fd9e40).
