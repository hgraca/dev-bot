---
date: 2026-10-06
keywords: ["git", "rebase", "squash"]
trigger-on: ["squash-subset-interleaved-commits"]
---

## Squashing a subset of commits on a shared branch: fold yours, pick theirs, verify tree identity

To squash only YOUR commits on a branch where other writers' commits are interleaved (and possibly
already pushed), run `git rebase -i <base>` with a hand-built todo: your first commit as `reword` (or
`pick`), every other commit of yours as `fixup` grouped immediately after it, then all other commits as
`pick` in their original order. Interactive-rebase `fixup` folds into the immediately preceding todo
line, so your commits must be grouped — leaving them interleaved makes each fold into someone else's
commit. Grouping does move your later blocks ahead of theirs; safe when the change sets are disjoint.
Set the squashed message with `GIT_SEQUENCE_EDITOR` (copy a prepared todo file) plus `GIT_EDITOR`
(write the message for the `reword`). Verify `git rev-parse HEAD^{tree}` is identical before and after
— squashing reorganises history without changing the tree. If a target is already on the remote this
rewrites pushed history: do it only when the human has agreed to force-push (`--force-with-lease`).

Classification gotcha when scripting it: `git log --format='%h %s' | grep '<subject>$'` also matches
`fixup! <subject>` (a suffix match), so select the real target with `^[0-9a-f]+ <subject>$`.
