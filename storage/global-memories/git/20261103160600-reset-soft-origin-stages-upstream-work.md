---
date: 2026-11-03
keywords: ["git", "reset-soft", "squash", "merge-base", "autosquash"]
aliases: ["reset --soft origin/main staged deletions", "squash staged upstream changes"]
---

## Squashing with `git reset --soft origin/<default>` stages everything main gained

Collapsing a branch's fixups with `git reset --soft origin/<default>` is wrong as soon as the remote default has advanced since the branch was cut. The reset moves HEAD to the _new_ tip while leaving the index untouched, so every path main gained since the fork point reappears in the index as a deletion, and the next commit folds the reverse of unrelated upstream work into the task's change.

Squash against the fork point instead:

```bash
BASE=$(git merge-base origin/<default> HEAD)
git log --oneline "$BASE"..HEAD   # must list only this task's commits
git reset --soft "$BASE"
```

`git status --porcelain` immediately after staging is the check: entries you did not create mean the base was wrong — reset and retry from the merge-base. The same moved base also invalidates a before/after `git diff | sha256sum` comparison, which is why the fixup-squash verification uses structural checks (see `git/20261102205200-autosquash-diff-hash-check-base-moved.md`).
