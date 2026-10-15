---
date: 2026-10-15
keywords: ["devbot", "release", "git-tag", "merge", "dirty-tree"]
aliases: ["FATAL merge the working tree is not clean", "tag.sh merge blocked by untracked files", "release blocked by a dirty tree"]
trigger-on: ["devbot-release", "git-tag-merge"]
---

## The release `merge` step refuses any dirty tree — untracked files included

`devbot:git-tag` / `devbot:gh-release` begin with `tag.sh merge`, which aborts with `FATAL: merge: the working tree is not clean` if the checkout has any uncommitted state; nothing is merged, tagged or pushed. The trap is that _untracked_ files trigger it too, even though the release is normally a fast-forward that would never touch them — the gate is a plain "is the tree clean" check, not a merge-safety check, so new but uncommitted files block it just as modified ones do. In dev-bot's own repo the usual culprit is a batch of untracked `storage/global-memories/*.md` captures. Clear them before releasing — commit them (they are the tracked shipped store) or stash them — then re-run; confirm with an empty `git status --porcelain`.
