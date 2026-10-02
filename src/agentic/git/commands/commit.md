---
name: devbot:commit
description: Commit the current changeset
---

Commit your changes in atomic commits, use fixup commits when you want to amend commits not yet in another branch,
and the conventional commits style.

If you are not already inside a linked git worktree, isolate the work first — follow the
`devbot:git-worktrees` policy (`tools/worktree.sh create <branch>`), then commit there.
