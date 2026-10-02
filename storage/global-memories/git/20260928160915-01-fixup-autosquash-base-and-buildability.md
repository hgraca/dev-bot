---
date: 2026-09-28
keywords: ["git", "fixup", "autosquash", "rebase", "history rewrite"]
trigger-on: ["git-fixup-commit", "git-autosquash", "history-rewrite"]
---

## Autosquash has two silent traps: the base, and the buildability of the intermediate commit

**(1) The base must be an ancestor of the oldest commit being modified.** Running `git rebase -i --autosquash <base>` with `<base>` set to the target commit itself (e.g. `--autosquash e0762db27` while the fixup targets `e0762db27`) puts that commit *outside* the rebase range, so its `fixup!` has no target: the todo list shows it as a stray `pick fixup! …` at the end and the fold never happens. Use `<target>^` (or the branch point) as the base. Always print the plan first — `GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <base>` prints the `pick`/`fixup` lines and aborts without touching history, which is exactly how the stray `pick` is caught.

**(2) A fixup cannot reference a file that a later commit introduces.** Folding moves the fixup's content to its target's position in history, so a fixup aimed at an *earlier* commit that edits, imports, or calls a class introduced by a *later* commit produces an intermediate commit that does not build (autoload/symbol errors). When a shared helper added mid-branch needs to be adopted by a file committed *before* it, record that adoption as a **standalone commit at the tip**, not a fixup — the "one fixup per correction" rule yields to the rule that every commit must build on its own.
