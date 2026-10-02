---
date: 2026-10-02
keywords: ["devbot", "release.sh", "git merge", "working tree"]
trigger-on: ["devbot-release", "release-script-merge"]
---

## `release.sh merge` aborts on a dirty tree even when the merge is a no-op

`release.sh merge` runs its clean-working-tree check (`git status --porcelain`) before the `source == default_branch` short-circuit, so a single untracked file aborts it with `FATAL: merge: the working tree is not clean` — even when there is nothing to merge. In a repo where `commit_memory` is on, freshly written memory notes under `.agents/memory/latent/**` are untracked and not gitignored, so they are exactly the kind of residue that triggers this. Only `merge` performs the check; `tag`, `push` and `release` do not. Fix: when the merge is provably a no-op (`main == origin/main`, no fixups), skip `merge` and go straight to `tag` → `push` → `release`. If the no-op path must actually run, move the untracked files aside to a temp dir with a restore trap, run `merge` (it prints `already on main — nothing to merge`), then move them back and confirm `git status --porcelain` matches the original entries. Avoid `git stash -u` as the shortcut when the files must keep their exact paths and modes.
