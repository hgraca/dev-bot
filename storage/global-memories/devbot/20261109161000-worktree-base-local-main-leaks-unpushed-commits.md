---
date: 2026-11-09
keywords: ["devbot", "worktree", "origin/main", "unpushed-commits", "pull-request-scope"]
aliases: ["worktree base local main", "PR carries unpushed commits"]
---

## A worktree based on local main carries that branch's unpushed commits into the PR

`worktree.sh create <branch> --base main` branches from the **local** `main`, so any commit that exists only locally — memory captures, another session's work — rides into the task branch and appears in the pull request. Confirmed 2026-11-09: a module PR contained four unrelated memory commits because the local default branch was ahead of `origin/main`. Base the worktree on `origin/main` (`--base origin/main`) unless the task truly depends on local-only commits, or rebase the branch onto `origin/main` before opening the PR (`git rebase --onto origin/main <first-local-only-commit> <branch>`). Check `git log --oneline origin/main..HEAD` before creating the PR: anything unrelated there will be reviewed as part of the change.
