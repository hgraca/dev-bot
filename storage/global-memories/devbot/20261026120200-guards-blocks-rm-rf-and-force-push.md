---
date: 2026-10-26
keywords: ["devbot", "guards", "rm", "blocked", "hook"]
---

## The guards module blocks `rm -rf` and force push — hand both to the human

dev-bot's `guards` hook rejects `rm -rf` outright (`[guards] Command blocked: rm -rf is blocked`), the same way it rejects `git push --force`/`--force-with-lease`. Both blocks are intentional and must not be routed around — no alternate recursive-delete tool (`find -delete`, `xargs rm`, a script), no `+refspec`, no different flag. Attempting a workaround defeats the guard's core intent.

When a task needs either, stop and give the human the exact command plus the reason it is safe, and let them run it. Reaching for another tool to accomplish the same deletion is the same violation as force-pushing through a refspec.

Removing a stale linked worktree is normally done with `git worktree remove <path>` + `git worktree prune`, which the guard does **not** block — prefer that over `rm -rf` when the directory is a registered worktree. An orphaned directory (no `.git` file, absent from `git worktree list`) can only be deleted with `rm -rf`, so that one always goes to the human.
