---
date: 2026-10-22
keywords: ["worktree", "devbot", "pull-request", "finish-flow", "push"]
see: ["ADRs/20261009111428-finish-flow-work-folder-reconciliation.md"]
---

## Worktree work finishes with a push and a pull request, never a local merge

`worktree.sh` used to end a task with `merge <branch>`, which required the main checkout to already be on the local default branch and refused otherwise; both the tool and the `git-worktrees` skill stated that precondition. That made the whole flow depend on a local state the task never reads — `create` cuts the branch from `origin/<default>` regardless of what the main checkout has checked out.

The finish flow is now `worktree push <branch>` (push the worktree branch and set its upstream) followed by opening a pull request against `<default>` with `devbot:gh-create-pr`. Nothing is merged, checked out, or otherwise changed locally, so a session is independent of the main checkout's branch, dirtiness, and history. `worktree merge` and its `--no-edit` path are gone; `remove` stays.

The worktree must survive the pull request being opened: review feedback is fixed in it, on the same branch, and removing the directory early strands that work. Remove it only after the user states the work is finished.
