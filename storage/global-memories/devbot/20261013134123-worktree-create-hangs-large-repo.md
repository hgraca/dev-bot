---
date: 2026-10-13
keywords: ["devbot", "worktree", "timeout", "git-fetch"]
trigger-on: ["devbot-worktree-create", "worktree-create-large-repo"]
---

## `worktree.sh create` can outlive a shell timeout on a large repo — but the worktree is already created

In a big repository (a full Laravel monorepo, for instance) `worktree.sh create <branch>` can hang past a 120s tool timeout, because the tool `git fetch`es `origin` before cutting the branch; the shell kills the command while it has printed nothing, so it reads as a failure when it is not. Check state before retrying: `git worktree list` and `git branch --list '*<slug>*'` usually already show the worktree and branch (at `.agents/worktrees/<branch-with-slashes-as-dashes>`), and a retry would then abort with "already exists". Confirm the new worktree is sane with `git -C <worktree> status -sb` (expect no upstream), then carry on. Next time run the create in a PTY with `notifyOnExit` so a slow fetch does not read as an error.
