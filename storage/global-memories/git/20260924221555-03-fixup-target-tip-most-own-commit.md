---
date: 2026-09-24
keywords: ["git", "fixup", "autosquash", "concurrent-agents"]
trigger-on: ["fixup-target-selection", "autosquash-conflict"]
---

## Target the tip-most of your own commits when recording fixups on a shared branch

`git commit --fixup=<sha>` records a commit whose subject names its target, and `git rebase --autosquash` later replays it directly after that target as a 3-way merge. On a branch where another session is committing concurrently, targeting an *earlier* commit relocates the fixup ahead of the peers' intervening commits, where the merge is against a tree the fixup was not written for — it usually still applies for disjoint edits, but the conflict risk is gratuitous. Targeting the tip-most commit you own keeps the replay at the exact tree state the fixup was authored against, so it applies cleanly; attributing a T3-derived fix to the T4 commit is a smaller cost than a conflicted release rebase, and the fixup's body or the report can carry the true attribution. Corollary: several fixups against one target share an identical subject, so state which fixup answers which finding in the report — the subject cannot carry that.
