---
date: 2026-10-09
keywords: ["devbot", "worktree", "git"]
aliases: ["worktree existing branch", "checkout remote branch worktree"]
trigger-on: ["git-worktree-existing-branch"]
---

## Checking out an existing remote branch into a worktree needs raw git

The devbot `worktree.sh create <branch>` tool always cuts a **new** branch from `origin/<default>` and refuses if the branch or path already exists, so it cannot check out a branch that already exists on the remote (e.g. reviewing or serving a teammate's feature branch). Use raw git instead: `git worktree add -b <branch> --track <worktree-path> origin/<branch>` — this creates the local branch tracking the remote. Put the path under the devbot worktrees dir (default `.agents/worktrees/<slug>`, already git-ignored) so the main checkout's `git status` stays clean, and run every later command with `-C <worktree>` / from the worktree root. The tool's finish subcommands (`merge`/`remove`) still apply to that branch afterward.
