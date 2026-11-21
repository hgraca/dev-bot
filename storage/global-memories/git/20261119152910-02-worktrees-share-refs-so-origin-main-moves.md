---
date: 2026-11-19
keywords: ["git", "worktree", "origin/main", "shared refs"]
trigger-on: ["shared-checkout-diffstat", "rebase-onto-origin-main"]
---

## Linked worktrees share refs, so origin/main moves under a long-running branch

Every worktree of a repository shares one ref store: `git fetch` run by any agent, in any
worktree, advances `origin/*` for all of them. A branch cut from `origin/main` an hour earlier
then diffs against a base that has moved, and `git diff --stat origin/main..HEAD` lists another
agent's merged files as if they were yours — with the sign flipped, they appear as deletions of
code you never touched. Nothing is wrong with the branch. Check `git log --oneline HEAD..origin/main`
before reading a diffstat, or diff against the merge-base (`git diff $(git merge-base HEAD
origin/main)..HEAD`). Rebase onto the newer `origin/main` when convenient, and expect the base
change to invalidate an already-green CI run after the force-push.
