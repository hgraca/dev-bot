---
date: 2026-07-30
keywords: ['git', 'staging', 'commit']
---

## git add + commit silently includes all pre-existing staged files

When you run `git add <file>` and then `git commit`, the commit includes ALL currently staged files — not just the one you just added. If the index already had other staged changes from before, they get committed too. Fix: `git reset HEAD -- .` first to clear the entire staging area, then `git add` only desired files. Alternatively use `git stash`, apply changes, stage selectively, commit, then `git stash pop`.
