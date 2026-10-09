---
date: 2026-10-09
keywords: ["devbot", "release", "tag", "worktree"]
aliases: ["tag.sh merge working tree is not clean", "release blocked by untracked file"]
trigger-on: ["devbot-release-flow"]
---

## `tag.sh merge` refuses a dirty tree — untracked files included

`tag.sh merge` (the git half of `devbot:gh-release` / `devbot:git-tag`) aborts with `FATAL: merge: the working tree is not clean` when `git status --porcelain` shows **anything**, including untracked files. A stale untracked backup such as `.devbot.project.jsonc~` at the repo root blocks the whole release before any VCS change is made. The release notes file is safe — gitignored via the `*no-vcs*` rule, so it does not count. Clear stray untracked files (ask the owner before deleting anything not yours) and re-run `merge`; the failed attempt changes nothing, so the approved plan still holds.
