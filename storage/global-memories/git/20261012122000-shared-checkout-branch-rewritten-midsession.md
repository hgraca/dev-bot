---
date: 2026-10-12
keywords: ["git", "shared-checkout", "force-push", "rebase"]
trigger-on: ["shared-checkout-base-drift"]
---

## A shared checkout's branch can be rewritten and force-pushed mid-session by another actor

In a shared working tree, another session or the human can rebase/squash and force-push the branch you are basing work on while you work. Symptom: `git status -sb` starts reporting `ahead N, behind 1` on a branch that was in sync, and `git reflog` shows a `rebase (start)` / `rebase (finish)` you never ran. The commits you built on become orphaned — present locally but on no remote ref. Before treating a branch as a stable base, and before any amend/reset/fixup, re-check `git rev-parse origin/<branch>` and `git log --oneline -1 origin/main`. If the remote moved, surface it to the human rather than resolving it yourself, then rebuild your work on the current tip.
