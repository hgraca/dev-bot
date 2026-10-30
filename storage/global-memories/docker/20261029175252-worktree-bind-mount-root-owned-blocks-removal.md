---
date: 2026-10-29
keywords: ["docker", "worktree", "permissions", "bind-mount", "git-worktree"]
aliases: ["git worktree remove permission denied", "root owned files in worktree"]
trigger-on: ["docker-bind-mount-into-worktree"]
---

## A docker bind mount creates root-owned files that block `git worktree remove`

Running `docker run -v "$WT":/app -v <host-vendor>:/app/vendor` against a git worktree makes docker create `/app/vendor` as a real directory inside that worktree, and whatever the container writes there can end up owned by uid 0. The worktree then cannot be removed: `git worktree remove` reports "failed to delete ... Permission denied" and `git worktree prune` does not help, because the directory still exists. Pass `-u "$(id -u):$(id -g)"` on every `docker run` and delete any bind-mount target the container had to create before removing the worktree; if root-owned files are already there, only `chown`/`sudo rm` clears them, so surface it rather than working around the guard.
