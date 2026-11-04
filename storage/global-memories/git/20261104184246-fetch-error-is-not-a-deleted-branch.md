---
date: 2026-11-04
keywords: ["git", "fetch", "prune", "remote-tracking"]
trigger-on: ["git-fetch-prune", "remote-tracking-ref"]
---

## A failed fetch is not evidence that a remote branch was deleted

`git fetch origin <branch> 2>/dev/null || true` collapses two unrelated outcomes: the branch really is gone (normal after a merge that deletes the head branch), and the fetch failed (auth, network, wrong remote). Treating both as "the ref is gone" leaves the old `origin/<branch>` in place, so a later `git rev-list origin/<branch>..HEAD` compares against that stale ref and reports the branch as fully pushed even though the real remote has moved on — an inference that can authorize deleting work that exists only there.

Use one unsuppressed `git fetch --prune origin` instead. `--prune` removes a remote-tracking ref only when the remote genuinely no longer has that branch, and an unreachable remote fails the command outright rather than pruning anything. Never infer a ref's absence from an error you suppressed to get there.
