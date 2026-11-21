---
date: 2026-11-20
keywords: ["git", "stale-branch", "worktree", "merge-conflict"]
aliases: ["branch cut from old master", "modify/delete conflict", "ci green on stale base"]
trigger-on: ["git-worktree-create", "branch-from-default"]
---

## A branch cut from a stale default edits files the default already deleted

Creating a branch or worktree from the local default branch without fetching first anchors the work to an old commit. The damage is worse than the usual stale-diff noise: when the default has since deleted or renamed the files the change touches, the branch edits paths that no longer exist upstream and the merge fails with `CONFLICT (modify/delete)`. Resolving that the wrong way — keeping "ours" — resurrects something that was deliberately retired, which is how a dead load balancer comes back to life.

Local CI cannot catch this. Checks run against the branch's own tree, which is internally consistent, so a green suite and a passing render say nothing about whether the branch merges. `git merge-base --is-ancestor origin/<default> HEAD` is the check that answers it, and it costs one command before any file is touched.

Fetch, then create: `git fetch origin <default>` and branch from `origin/<default>` rather than the local ref, which may itself be behind. The same blindness affects any diff taken against a stale working tree — `git diff origin/<default> -- <path>` in a checkout that is behind reports phantom additions and deletions, so confirm which tree a surprising diff came from before believing it.
