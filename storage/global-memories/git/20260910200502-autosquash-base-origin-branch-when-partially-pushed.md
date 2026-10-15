---
date: 2026-09-10
keywords: ["git", "autosquash", "rebase", "fixup", "origin"]
trigger-on: ["git-autosquash-base", "squash-fixups"]
superseded_by: ["git/20261015154453-autosquash-rewrite-boundary-is-first-fold.md"]
---

## Autosquash a partially-pushed branch from origin/<branch>, not main

> **Superseded in part by** `git/20261015154453-autosquash-rewrite-boundary-is-first-fold.md` (2026-10-15) — basing on `main` does not rewrite commits below the first folded fixup, so the "replays every commit … forcing a force-push" claim holds only when a fold lands at or below the pushed tip. Basing on `origin/<branch>` remains the tighter, more defensive base.

When a branch has some commits pushed and some local fixups, `git rebase -i --autosquash main` replays _every_ commit since main — rewriting the already-pushed ones and forcing a force-push of history others may track. First find what is actually local with `git log --oneline origin/<branch>..HEAD`, and confirm no fixup is pushed (`git branch -r --contains <sha>` prints nothing). Then base the rebase on the pushed tip: `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<branch>`, which rewrites only the unpushed commits. Verify content was untouched by comparing the cumulative diff hash before and after: `git diff origin/<branch>..HEAD | git hash-object --stdin` must be identical. To review the fold plan without executing, run the rebase with `GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false'` — it prints the todo list then aborts.
