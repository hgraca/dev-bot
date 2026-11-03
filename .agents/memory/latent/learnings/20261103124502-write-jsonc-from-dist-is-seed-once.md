---
date: 2026-11-03
keywords: ["devbot", "opencode.jsonc", "reinit", "seed-once"]
aliases: ["_write_jsonc_from_dist", "config template", "dist template"]
---

# `_write_jsonc_from_dist` is seed-once — reinit never overwrites a project's config

`_write_jsonc_from_dist` in `src/harnesses/opencode/init.sh` returns early with `_skip "<name> already exists"` when the target file is present. So `devbot init`/`devbot reinit` only seed `opencode.jsonc` and `.opencode/tui.json` on first creation; an existing file is treated as user-owned and left untouched.

Consequences:

- A hand-edit to a project's `opencode.jsonc` (models, `snapshots`, permissions) survives every reinit — it is not regenerated from `src/harnesses/opencode/opencode.dist.jsonc`.
- Changing a default for **existing** projects requires editing each project's `opencode.jsonc` directly; editing the dist only affects projects created afterwards.
- The dist is copied with comments stripped (string-aware) and `__DEV_BOT_ROOT__` / `__GPU_ENABLED__` substituted, so template comments never reach the generated file.
