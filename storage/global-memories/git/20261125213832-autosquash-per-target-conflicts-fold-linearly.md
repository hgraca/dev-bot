---
date: 2026-11-25
keywords: ["git", "autosquash", "fixup", "rebase", "todo-format"]
aliases: ["fixup squash conflicts", "autosquash no-op", "GIT_SEQUENCE_EDITOR sed"]
---

## Per-target autosquash fails when the target's files changed again; fold linearly instead

`git rebase -i --autosquash` moves each `fixup!` commit next to the commit it names and squashes it
there. That only applies cleanly when the target is the **last** commit touching those files: a
fixup recorded at the branch tip carries a diff against the tip, and replaying it on top of an
earlier commit whose files were modified by every commit in between produces a genuine content
conflict — not a spurious one. Observed twice on one branch (dev-bot #184, #185): two fixups
targeting `cf82333c` and `366c1eac` conflicted even though the fixups themselves had correct content.

The conflict-free rewrite is to fold **in author order** rather than into the named target: rewrite
the todo so every `pick <sha> … fixup! …` becomes `fixup <sha> …`, which squashes each fixup into the
commit immediately before it. The tree is unchanged at every step, so nothing can conflict, and the
resulting history carries no `fixup!` subjects.

**Second trap — the todo format.** This git writes todo lines as `pick <sha> # <subject>`, with a
literal `#` between the SHA and the subject. A `sed -E 's/^pick ([0-9a-f]+) (fixup!.*)/…/'` pattern
therefore matches **nothing**, and the rebase reports success having replayed every commit unchanged
— the tell is the same SHAs in `git log` afterwards. Match `^pick ([0-9a-f]{7,40}) # (fixup!.*)$`, or
capture the todo once and inspect what git actually wrote before trusting a silent rewrite.
