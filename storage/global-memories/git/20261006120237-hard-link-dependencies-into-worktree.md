---
date: 2026-10-06
keywords: ["git", "worktree", "hard-link", "cp", "dependencies"]
trigger-on: ["worktree-dependency-hard-linking", "git-worktree-remove"]
---

## Hard-link dependency trees into a git worktree, and ignore them in the worktree's own exclude

A fresh `git worktree` checkout has only tracked files, so gitignored dependency trees (`vendor/`, `node_modules/`) are absent. `cp -al <base>/<dir> <worktree>/<dir>` mirrors each dir as real directories whose files are hard links into the base checkout — fast, no reinstall, and the two trees stay byte-identical without copying data. Two traps: the hard links share inodes, so a process that **writes** into the mirrored dir mutates the base checkout's copy (treat linked deps as read-only); and if the dir is not in the repo's ignore rules it shows as untracked in the worktree, which makes `git worktree remove` refuse with "contains modified or untracked files". Fix the second by writing the linked dirs into the worktree's per-worktree exclude — `git -C <worktree> rev-parse --git-path info/exclude` resolves to `<main>/.git/worktrees/<slug>/info/exclude` — so the entries are scoped to that worktree and ignored files never block removal. Reject absolute and `..`-containing source specs before `cp`, so a failed copy's cleanup cannot `rm -rf` outside the worktree.
