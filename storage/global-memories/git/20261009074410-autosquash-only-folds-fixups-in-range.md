---
date: 2026-10-09
keywords: ["git", "rebase", "autosquash", "fixup"]
aliases: ["fixup not squashed", "autosquash out of range"]
trigger-on: ["squash-fixup-commits"]
---

## `git rebase --autosquash` folds only fixups whose target is inside the rebased range

`git rebase -i --autosquash <base>` reorders and folds a `fixup!`/`squash!` commit only when its target commit is also inside `<base>..HEAD`. A fixup whose target is already pushed (at or below `<base>`) is left untouched — the branch keeps the `fixup!` and a plain `rebase --autosquash` silently does not clean it. To fold it, move `<base>` below the target (e.g. `<target>^`), which then rewrites that pushed commit and requires a force push. Practical consequence: "squash the fixup commits" is ambiguous when a branch carries a fixup for already-pushed history — the base you choose decides whether pushed history is rewritten, so confirm the intended scope before running it.
