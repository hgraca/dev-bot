---
date: 2026-08-31
keywords: ["devbot", "commit_memory", "config-merge", "gitignore"]
---

# commit_memory was read from project config only — global value ignored

`commit_memory` (gates whether `.agents/memory/` is blanket-ignored in `.git/info/exclude` via `memory/init.sh`) was read with `jq -r '.commit_memory // false'` from `.devbot.project.jsonc` only, so setting it `true` in `.devbot.global.jsonc` had no effect unless the project file also said `true`. Fixed in `cd366a47`: the read goes through `_devbot_get_config` (project-first, global-fallback), the dead duplicate read in `src/tools/devbot-cli/init.sh` was removed, `commit_memory` was added to `.devbot.global.dist.jsonc`, and `docs/configuration.md` now documents the precedence. When touching config reads in this repo, use `_devbot_get_config <key> [project_dir]` — a project-only read of `.devbot.project.jsonc` is the bug pattern this fixes.
