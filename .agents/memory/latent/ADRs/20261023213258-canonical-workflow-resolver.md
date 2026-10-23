---
date: 2026-10-23
keywords: ["workflow", "resolver", "worktrees", "migration", "devbot"]
aliases: ["_devbot_get_workflow", "workflow precedence", "worktrees migration"]
see: ["PDRs/20261023213258-workflows-and-check-ins.md"]
---

## One legacy-aware workflow resolver, migrated before the reconciler

`_devbot_get_workflow` in `src/_shared/functions.sh` is the single implementation of workflow resolution: a project's `workflow` key, then that same file's retired `worktrees` boolean (`true` → `worktrees`, `false` → `trunk`), then `.devbot.global.jsonc` in the same order, then `worktrees` — so a project's intent wins across both keys even when the global config is already migrated. `worktree.sh enabled` exposes it as exit 0 (`worktrees`), 1 (`trunk`) and 2 (unknown — callers stop and ask), and `project-for-path`, `/commit` and the memory skills delegate to that same resolution instead of reading the key themselves. Because a failed migration leaves the old key in place, the fallback is the safety net: `devbot update` migrates the global config and every registered project with a JSONC tokenizer (comments and strings skipped, only the real top-level property's key and boolean rewritten, file mode preserved) **before** the global reconciler, and skips reconciliation entirely when the migration needs attention — otherwise the reconciler would drop the retired key and copy the dist default, silently flipping a trunk project to worktrees.
