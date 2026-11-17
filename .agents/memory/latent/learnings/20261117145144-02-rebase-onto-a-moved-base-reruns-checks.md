---
date: 2026-11-17
keywords: ["worktree", "rebase", "autosquash", "force-push", "checks"]
---

# A pre-merge squash keeps the tree only while the base has not moved

## The invariant

`devbot:gh-review-loop` finishes by squashing fixups and handing the human a `--force-with-lease` push, justified by "a squash rewrites commits without changing the tree, so the checks stay green". That holds only against the same base.

## What actually happens

`worktree.sh create` bases a branch on `origin/<default>` at creation time, and `git rebase -i --autosquash origin/main` rebases onto the base as it is _now_. When `main` advanced while the branch was open, the rebase folds the fixups **and** replaces the base, so the new head's tree differs from the reviewed one by everything that landed upstream and CI re-runs. Verify the part that must not change instead: `git diff <pre-rebase-sha> <post-rebase-sha> -- <touched paths>` empty means the authored content is byte-identical, and `git diff --stat origin/main..HEAD` should list only the PR's own files. Say that CI will re-run rather than claiming it cannot.
