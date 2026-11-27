---
date: 2026-11-26
keywords: ["git", "worktree", "origin/main", "stale-ref", "copy"]
aliases:
  [
    "worktree cut from origin while main is behind",
    "reverting upstream by copying files",
  ]
---

## Copying files from a stale main checkout reintroduces content upstream reverted

`worktree.sh create` cuts a worktree from `origin/<default>`, but the main checkout can be several commits behind it. Moving an in-progress edit into the worktree with `cp` therefore carries the **whole file as it was on the stale local branch**, including upstream changes that the newer `origin/<default>` had already reverted or sanitised. Symptom: the worktree diff shows hunks in files you never edited, and tests that were green on the worktree's HEAD fail. Diagnose with `git log --oneline HEAD..origin/main` inside the worktree — anything listed is absent from your copy's view; if the copy produced foreign hunks, restore those paths from the worktree HEAD (`git checkout -- <path>`) and re-apply only your own edits. Same reasoning applies to any `--force`-free fast-forward: check the ref you copy from, not the ref you think you are on.
