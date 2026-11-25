---
date: 2026-10-24
keywords: ["git-fixup-commits", "fixup", "memory-commits", "pr-stage", "commit-policy"]
aliases: ["fixup versus fix commit", "memory vault commits", "squash before merge"]
---

## PR-stage corrections are fixups; memory commits are normal commits

> **Superseded in part (2026-11-25).** Memory commits are published on a memory pull request by
> `devbot:commit-memories`; the fixup rule below stands.

A correction is recorded as `fixup!` whenever its target commit is not reachable from the default branch or from any other branch — pushed status is irrelevant, only reachability matters. Fixups accumulate on the PR branch, are squashed against `origin/<default>` (never the local default, which may hold stranded memory commits) just before merge, and the rewrite is published by the human with an explicit-OID `--force-with-lease` because the guards module blocks force-pushes for the agent. Memory-vault commits are the opposite case, and their old rule is **retired** (2026-11-25): they were normal commits containing only the memory files, made on the main checkout's local default branch while it was checked out there, never as fixups — `devbot:commit-memories` publishes them on a memory pull request instead. The agent surfaces any stranded commit; the human decides how it reaches origin.
