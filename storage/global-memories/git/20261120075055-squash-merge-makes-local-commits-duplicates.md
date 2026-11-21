---
date: 2026-11-20
keywords: ["git", "squash-merge", "rebase", "pull-rebase", "conflict"]
aliases: ["pull rebase conflicts on merged branch", "duplicate commits after squash", "skip duplicate commits"]
trigger-on: ["git-pull-rebase-after-merge", "squash-merge-followup"]
---

## After a squash merge your local branch commits are duplicates — skip them, do not resolve the conflict

A pull request merged with squash landing turns the branch's N commits into one new commit with a different hash, so the local copies of those commits stay "ahead of origin" while their content is already upstream. The next `git pull --rebase` replays them onto a base that already contains the same change and conflicts in every file it touched — which reads as "upstream changed the same lines", but there is no work left to apply. Resolving those hunks by hand is the wrong move: it can re-introduce a version upstream already improved on (a superseded fix of the same bug, for instance). Confirm the content is upstream first (`git show origin/main:<path> | grep <distinctive-symbol>`), then `git rebase --skip` each duplicate — including any commit upstream superseded with a better fix — and let unrelated local commits replay normally. Verify afterwards that `git diff origin/main -- <paths>` is empty for the files the PR touched and that the suite is green; the rebase then leaves only the commits that genuinely are not upstream.
