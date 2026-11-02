---
date: 2026-11-02
keywords: ["git", "worktree", "worktree-remove", "permission-denied", "recovery"]
aliases: ["worktree remove not atomic", "worktree left unregistered", "recreate worktree admin files"]
trigger-on: ["git-worktree-remove"]
---

## `git worktree remove` deletes before it fails

Removal is not atomic. `git worktree remove` first deletes the registration (`.git/worktrees/<name>`, which holds the worktree's `index`) and begins deleting the checkout's files, then aborts on the first undeletable path — typically a root-owned cache written by a container (`storage/cache`, `node_modules`). The result is worse than a plain failure: the directory is orphaned (it drops out of `git worktree list`), partly emptied, and `git worktree repair` cannot re-adopt it because the admin entry it would repair is already gone.

What survives: branch refs are untouched, so all committed work is safe; and because removal refuses a dirty worktree without `--force`, the aborted run does not destroy uncommitted changes.

Recovery in place, no root needed: recreate `<repo>/.git/worktrees/<name>/` with `gitdir` (absolute path to the worktree's `.git` file), `HEAD` (`ref: refs/heads/<branch>`), and `commondir` (`../..`), then run `git reset --hard` inside the worktree. That rebuilds the index and restores every missing tracked file; ignored files that were not deleted are reused as-is.

A clean worktree is not evidence of staleness — another agent may be mid-task on committed work. Remove only worktrees this session created, or ask first.
