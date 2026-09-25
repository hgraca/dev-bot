---
date: 2026-09-25
keywords: ["git", "commit", "index", "parallel-session", "pathspec"]
trigger-on: ["git-commit-shared-worktree"]
---

## `git add <paths>` does not clear the index — a bare `git commit` still sweeps another session's staged work

On a worktree shared with a parallel agent, `git add <your paths>` followed by a bare `git commit` is not safe: `git add` only *adds* entries and never removes what another process has already staged. Seen when a parallel session had two `R100` renames staged mid-move — a `git commit` meant to record two new memory files also committed those renames, producing a `docs(memory)` commit that silently carried unrelated refactor moves, and emptying the other session's index so its next commit would have missed them. Two traps hide it: the staged entries DO appear as `R ` lines in `git status --short`, but only if you read the index rather than the working tree, and a `git add <paths>` immediately beforehand reads as if it scoped the commit. Fix: commit with a pathspec so the index is isolated — `git commit --only -m <msg> -- <path>…` records only the named paths and leaves every other staged entry untouched. Verify with `git show --name-status HEAD` (only your paths) while `git diff --cached --name-status` still lists the other session's entries. To correct a commit that already swept them: `git reset --soft HEAD~1` then `git commit --only -- <your paths>`, which restores the foreign staged entries exactly as they were.
