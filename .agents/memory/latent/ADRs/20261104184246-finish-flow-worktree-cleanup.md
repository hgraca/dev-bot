---
date: 2026-11-04
keywords: ["reconcile-work", "worktree", "finish-flow", "branch-cleanup"]
see: ["ADRs/20261009111428-finish-flow-work-folder-reconciliation.md"]
---

## The finish flow removes landed worktrees and their local branches

`devbot:reconcile-work` gained a first step that sweeps every worktree under the owning project's `<devbot_dir>/worktrees/` and takes down the landed ones. It runs before the LSP reap, so the reap collects the servers whose working directories it just deleted.

Removal is gated on state, never on authorship. A worktree goes only when its tree is clean, nothing is unpushed or remote-only, and the work is landed: a merged pull request, or, with no pull request, the branch an ancestor of the refreshed `origin/<default>`. A merged PR doubles as the push evidence, because its head branch is usually deleted on merge and the absent ref must not block the cleanup. An open PR, uncommitted work, or an unreadable `gh`/fetch keeps the worktree and is reported. The local branch is deleted with `-D` (a squash-merge is not ancestry) and only after the worktree is gone; remote branches are never deleted.

Rejected: a per-session ledger stamped by `worktree.sh create` — strict attribution, but it misses leftovers from earlier or crashed sessions, which is the accumulation being fixed; and a new skill of its own — it would only wrap `git-worktrees` §Finish, which stays the canonical procedure.
