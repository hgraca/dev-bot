---
date: 2026-10-06
keywords: ["worktree", "git-worktrees", "dependencies", "hard-link", "devbot"]
see: ["PDRs/20261002213005-shared-working-tree-commit-rule.md"]
---

## Worktrees hard-link dependency dirs from the main checkout

A linked worktree contains only tracked files, so gitignored dependency trees are absent and the worktree cannot build or test without a re-install. `worktree.sh create` now hard-links the dependency dirs from the main checkout with `cp -al`, defaulting to `vendor` and `node_modules`; a repeatable `--link <dir>` replaces the defaults for other ecosystems (`.venv`, `target`, `libs`) and `--no-link` disables it. Linking is best-effort and non-fatal: a missing source dir, an existing destination, or a failed copy emits `WARN:` and continues. Linked dirs are registered in the worktree's own `info/exclude` (`git -C <wt> rev-parse --git-path info/exclude`) so they never show as untracked or block `git worktree remove`. The files share inodes with the main checkout, so a build that writes into a linked dir also mutates the main copy — deps are treated as read-only. `--link` values must be relative and free of `..` (a bad value is refused with `FATAL:`) to keep the failure-path `rm -rf` inside the worktree. The skill also directs builds and tests through a worktree-scoped container so parallel agents do not share one.
