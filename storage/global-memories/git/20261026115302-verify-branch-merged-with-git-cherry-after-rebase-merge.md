---
date: 2026-10-26
keywords: ["git", "patch-id", "rebase-merge", "branch-cleanup"]
aliases: ["git cherry", "is branch merged", "rebase and merge sha rewrite"]
---

## A rebase-merge rewrites SHAs, so ancestry checks call a merged branch unmerged — use `git cherry`

Never conclude a PR branch is unmerged from `git rev-list --count <upstream>..<branch>` or a refused `git branch -d`: when a PR is merged with "Rebase and merge" (or the branch was rebased before merging), every commit gets a new SHA, so the old commits are not ancestors of the target branch even though their patches are all upstream. The reliable check is patch-id based — `git cherry <upstream> <branch>` prints one line per commit, `-` meaning that patch is already upstream and `+` meaning it is genuinely missing; delete the branch only when no `+` lines remain (then `git branch -D`, since `-d` will still refuse). Worked example: a 13-commit feature branch merged as 8 rebased commits left two worktree branches reporting "8 commits not in origin/main" and blocking `git branch -d`, while `git cherry origin/main <branch>` marked all 16 lines `-` — the branches were fully merged. The same trap applies to `git worktree remove` clean-up decisions.
