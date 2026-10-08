---
date: 2026-10-08
keywords: ["git", "rebase", "pull", "shared-checkout", "unstaged"]
trigger-on: ["git-rebase", "git-pull", "shared-working-tree"]
---

## A dirty tree blocks `git rebase`, but not `git pull --ff-only`

`git rebase <upstream>` refuses outright — "cannot rebase: You have unstaged changes" — and `--autostash` is the wrong answer in a shared checkout, because it stashes and re-applies work that belongs to someone else. `git pull --ff-only` has no such guard: it fast-forwards and carries an unrelated modified file across untouched, so it is the primitive to reach for when another party may hold uncommitted changes in the same checkout. Verified on three repos each carrying a modified `Makefile`: all three fast-forwarded cleanly and the file was still modified afterwards.

Pair it with a hard rule — never `git add` another party's file. Stage your own paths explicitly (`git add composer.json composer.lock`, plus a filtered `git diff --name-only | grep … | xargs -r git add`), then confirm with `git show --name-only HEAD` that their file is absent. Their file still showing as modified in `git status --porcelain` after your commit is the proof you left it alone.
