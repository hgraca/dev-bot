---
date: 2026-10-02
keywords: ["git", "update-ref", "rebase", "worktree", "reflog"]
aliases: ["remove commits from shared branch", "interleaved commits", "history rewrite others working"]
trigger-on: ["git-remove-shared-branch-commits"]
---

## Removing your commits from a branch others are actively using, without touching their uncommitted work

To extract interleaved commits from a shared local branch while another worker has uncommitted files: build the rewritten history in a throwaway detached worktree (`git worktree add --detach <dir> <tip>`, then `git rebase -i <base>` dropping your commits via a `GIT_SEQUENCE_EDITOR` sed), then swap the ref atomically with `git update-ref refs/heads/<branch> <new> <old>` — passing `<old>` makes it fail if the branch moved meanwhile, so a concurrent commit is never clobbered. Do the swap from outside the checked-out worktree. Finally reset only your files in the working tree (`git checkout HEAD -- <modified>` plus `git rm` for the files you added) instead of stashing, leaving the other worker's uncommitted files byte-identical. Dropping an ancestor commit necessarily rewrites the SHAs of every commit above it; the other worker must reset, but their working-tree files are unchanged.
