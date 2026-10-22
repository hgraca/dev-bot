---
date: 2026-10-22
keywords: ["git", "worktree", "branch", "glob", "stale-checkout"]
trigger-on: ["git-worktree-work", "reading-repo-state"]
---

## A glob over .agents/worktrees picks the wrong worktree, and a stale main checkout lies

In a repo with several linked worktrees, `ls -d .agents/worktrees/*/ | head -1` returns whichever directory sorts first — usually another task's or another agent's worktree. Reading and committing there silently operates on the wrong branch. This happened twice in one session: once selecting another agent's worktree, once reading a main checkout parked on a stale feature branch (`improve-logging`) and concluding the service ran Laravel 10 / PHP 8.2 when `origin/main` had Laravel 13 / PHP 8.5.

Construct the path explicitly from the branch slug (`<repo>/.agents/worktrees/<branch-with-slashes-dashed>`) and confirm with `git -C <path> rev-parse --abbrev-ref HEAD` before reading anything. For facts about the default branch, read the worktree cut from `origin/<default>` or `git show origin/<default>:<file>` — never the main checkout's working tree, whose checked-out branch may be arbitrarily behind or ahead.
