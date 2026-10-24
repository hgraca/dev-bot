---
date: 2026-10-24
keywords: ["devbot", "worktree", "supervisor", "push", "project-flag"]
aliases: ["worktree push supervisor", "no worktree at", "--project ignored"]
trigger-on: ["devbot-worktree-push", "supervisor-worktree-commands"]
---

## `worktree.sh push` and `remove` resolve the repo from cwd, not `--project`

`worktree.sh create` and `enabled` accept `--project <owner>`, but `push`, `remove` and `list` do not — they resolve the main checkout from the current directory (`_git_root`). In a supervisor session, running `bash src/agentic/git/tools/worktree.sh push <branch> --project <owner>` from the supervisor root silently treats `--project` as a positional extra and fails with `FATAL: push: no worktree at <supervisor>/.agents/worktrees/<slug>`. The error names the supervisor's worktree path, so it reads as a missing worktree rather than a wrong working directory. Fix: run the command with cwd inside the owning project (`cd <owner>` first, or `bash <owner>/src/agentic/git/tools/worktree.sh push <branch>`), so `_git_root` finds the owner's main checkout; the same applies to `remove`.
