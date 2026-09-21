---
date: 2026-09-21
keywords: ["devbot", "release", "global-memories", "untracked-files", "working-tree"]
trigger-on: ["devbot-release", "release-merge-dirty-tree"]
---

## `release.sh merge` refuses on untracked files, and other projects leave untracked memory notes in the shared store

`cmd_merge` guards with `[[ -z "$(git status --porcelain)" ]]` (release.sh around line 397), which counts **untracked** files — so an otherwise-clean tracked tree still fails with `FATAL: merge: the working tree is not clean`. In the dev-bot checkout that hosts the shared global knowledge base this is not a rare state: every project's `latent/global` symlinks to `<dev-bot>/storage/global-memories`, so a session running in **another** project writes its global memory notes straight into this repository, where they sit untracked until someone commits them here. Observed cutting 1.5.1: five notes from a PHP/Composer session blocked the merge, and their `2026092109000x` filename timestamps did not match their write times (~11:50), so mtime plus the frontmatter keywords — not the filename — is what identifies the writer. Before starting a release run `git status --porcelain` and expect entries you did not create; then decide explicitly whether to commit them (they become part of the release) or to stash them (`git stash push -u -- storage/global-memories`, which leaves the released content unchanged and restores the files afterwards). Note too that a session working in a different checkout cannot commit files that land here at all, so they are orphaned rather than pending someone's commit.
