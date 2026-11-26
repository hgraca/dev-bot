---
date: 2026-11-26
keywords: ["devbot", "finish-flow", "worktree", "symlink-farm", "merge"]
---

## A merged task worktree can be the only local copy of the merged code

A pull request can merge while the main checkout is still behind `origin/main` — other work landed,
or local commits keep it from fast-forwarding. The harness's skill farm points at that stale checkout,
so a skill merged by the PR is not loadable from the main checkout even though the worktree that
carried it has the merged file.

During the finish flow, read the merged skill from the task worktree (or
`git show origin/main:<path>`) and follow it there. Let `devbot:reconcile-work` remove the worktree
only after the finish flow has used it; removing it first strands the only local copy of the merged
instructions until the user updates the main checkout.
