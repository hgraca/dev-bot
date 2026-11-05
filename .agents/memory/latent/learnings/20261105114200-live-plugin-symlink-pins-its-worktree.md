---
date: 2026-11-05
keywords: ["devbot", "worktree", "tui-plugins", "symlink", "reinit"]
aliases: ["worktree removal blocked by live plugin", "relink before remove"]
---

# A live TUI plugin's symlink pins the worktree it points into

While trialling an unmerged harness plugin, `.opencode/tui-plugins/<name>` is a symlink into the worktree that produced it (see `learnings/20261105100452-reinit-drops-unmerged-tui-plugin-links.md`). Removing that worktree after the PR merges dangles the link, and the next `devbot reinit` does not repair it — init's farm list still comes from the **main checkout**, which lacks the plugin until `main` carries the merge commit.

## Order that works

1. Bring the merged commit into the main checkout (`git -C <owner> merge origin/main`, or the human pulls).
2. Run `devbot reinit`, so `_link_tui_plugin` rewrites the link to `src/harnesses/opencode/<name>` in the main checkout.
3. Verify: the plugin's `modified` in `plugin-meta.json` equals the main checkout's file mtime, and `load_count` increments after a restart.
4. Only then `worktree.sh remove <branch>` and delete the local branch.

Skipping to step 4 leaves a dangling symlink and a plugin that silently fails to load on the next start. A main checkout that has diverged — unpushed memory commits plus a remote merge — cannot fast-forward; ask the human which way to reconcile rather than rebasing their commits.
