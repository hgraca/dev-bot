---
date: 2026-09-27
keywords: ["git", "rebase", "autosquash", "fixup", "conflict"]
trigger-on: ["git-autosquash-fixup-conflict"]
---

## rebase --autosquash conflicts when the fixup's context includes later commits

A `git commit --fixup=<target>` diff is authored against the CURRENT tree, so its
hunk context can include lines that LATER commits added. Autosquash moves the
fixup to sit right after its target, where that context does not exist yet — the
context lines then appear as additions and git raises a conflict (here: a test
file where a later commit had appended a section beneath the fixup's insertion
point).

Resolve by keeping ONLY the lines that belong to the target commit and dropping
the later-commit content from the conflict block; the later commit re-adds its
own section when it replays. Verify the rewrite preserved content with
`git diff --stat <pre-rebase-HEAD> HEAD` — it must be empty. Two fixups touching
adjacent regions of one file cascade the same way; resolve serially with
`git rebase --continue`.
