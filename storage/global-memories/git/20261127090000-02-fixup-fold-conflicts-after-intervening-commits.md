---
date: 2026-11-27
keywords: ["git", "fixup", "autosquash", "rebase", "conflict"]
---

## A fixup authored against a later tree cannot be folded into its target past an intervening commit

`git commit --fixup <target>` records the correction as a diff against the current tree. Autosquash
replays that diff at the target's position in history, where the surrounding lines may not exist yet —
typically because a commit _after_ the target rewrote the same paragraph or table. The rebase stops with
a conflict that has no correct mechanical resolution: `-X theirs` loses the later commit's edit, and
resolving by hand means inventing an intermediate version of the file that never existed.

Two ways out, both honest: (a) squash the whole branch into one commit — the tree that was reviewed is
preserved and no intermediate state is fabricated; or (b) keep the fixup unapplied until after the later
commit, accepting that it is no longer a fixup. When picking (a), verify `git rev-parse HEAD^{tree}` is
unchanged, so the squash is provably content-preserving. Reserve fixups for corrections made _before_ the
commits that touch the same text, or for single-commit branches.
