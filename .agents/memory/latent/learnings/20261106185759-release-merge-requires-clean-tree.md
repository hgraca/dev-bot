---
date: 2026-11-06
keywords: ["tag.sh", "release", "clean-tree", "untracked"]
aliases: ["merge: the working tree is not clean", "release blocked by untracked file"]
---

# A release merge needs a fully clean tree, untracked files included

`tag.sh merge` gates on `[[ -z "$(git status --porcelain)" ]]`, so an untracked file counts as dirty and aborts the release with `FATAL: merge: the working tree is not clean` — even when every tracked file is committed and the merge would be a no-op fast-forward.

The trigger here was `.devbot.global.jsonc~`, a stray backup of the gitignored runtime config that had been sitting in the checkout for days; `git status` showed nothing else, so the failure looks unrelated to the release. Clear the tree before the first release step, and if the file is not yours, ask before deleting it rather than discarding someone else's work.

The gate lives only in `merge`; `tag`, `push` and `release` do not re-check, so clearing the tree once unblocks the rest of the sequence.
