---
name: devbot:commit
description: Commit the current changeset
---

Commit your changes in atomic commits, and use the conventional commits style. A correction to a
commit unique to the current branch — including one already pushed on a branch with an open pull
request — is a fixup against that commit, not a new `fix(...)` commit (`devbot:git-fixup-commits`).

Commit where the project's workflow puts the work. Resolve it with
`bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" enabled` — never read the config keys
yourself, because the resolver also honours a not-yet-migrated `worktrees` key:

- **exit `0`** — the `worktrees` workflow: if you are not already inside a linked git worktree, isolate
  the work first by following `devbot:git-worktrees` (`tools/worktree.sh create <branch>`), then commit
  there.
- **exit `1`** — the `trunk` workflow: confirm the current checkout is on the default branch, then
  commit there; create no worktree and no branch. Not on the default branch: stop and ask — never
  record trunk work on a feature branch.
- **exit `2`** — the configured workflow is unknown: stop and ask; never guess.

In a `supervisor: true` session, resolve the owning project of the files you are committing first and
pass it — `worktree.sh enabled --project <owner>` — then run the git commands there (`git -C <owner>`);
the tool refuses a supervisor root.
