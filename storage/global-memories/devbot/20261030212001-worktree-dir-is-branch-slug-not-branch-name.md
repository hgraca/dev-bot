---
date: 2026-10-30
keywords: ["devbot", "worktree", "slug", "git-worktrees", "path"]
aliases: ["vanished worktree", "worktree directory disappears", "No such file or directory worktree"]
trigger-on: ["devbot-worktree-path", "git-worktree-path"]
---

## The worktree directory is the branch's slug, not the branch name

`worktree.sh create feat/login` puts the checkout at `<devbot_dir>/worktrees/feat-login` — every
character outside `[A-Za-z0-9._-]` becomes `-`. A path rebuilt from the branch name
(`…/worktrees/feat/login`) therefore points at nothing, and `git -C <that path>` fails with
`fatal: cannot change to '…': No such file or directory` (Python: `FileNotFoundError`). That error
looks like the worktree vanishing mid-command, and it is easy to blame the filesystem; `git worktree
list` and `ls` of the _parent_ keep succeeding, because the worktree is registered and its real
directory exists — only the branch-shaped path is wrong.

Verification recipe: compare the failing path against `git worktree list` (or
`worktree.sh path <branch>`, which reads the registration). If they differ by the slug, it was never
a filesystem problem. Two further failures share this shape: a relative destination given to
`git -C <repo> worktree add` resolves inside `<repo>` and nests (`repo/repo/.agents/worktrees/x`), and
a relative path given to `git worktree remove` reports `is not a working tree` for a worktree that is
registered.

Rule: never rebuild a worktree path — take it from `create`'s stdout, `worktree.sh path <branch>`,
`worktree.sh list`, or `git worktree list`. In dev-bot, `path`, `push` and `remove` all resolve from
the registration and reject the primary checkout, a stale registration, and a path that now holds a
different branch.
