---
date: 2026-11-26
keywords: ["git", "shallow-clone", "origin-ref", "worktree"]
---

## A tag-only shallow clone has no origin/<branch> remote-tracking ref

`git clone --depth 1 --branch <tag>` leaves a detached HEAD and writes
`remote.origin.fetch=+refs/tags/<tag>:refs/tags/<tag>`. `git fetch origin` and
`git fetch --unshallow --tags origin` create no `refs/remotes/origin/<branch>`, so a later
`git worktree add … origin/<default>` fails with `fatal: invalid reference`.

Fetch the branch with an explicit refspec:

```bash
git fetch origin "+refs/heads/<branch>:refs/remotes/origin/<branch>"
```

Use `--depth 1` only when `git rev-parse --is-shallow-repository` prints `true` (the installed
toolkit is shallow); a full clone must not be made shallow by the fetch. The same trap affects
`worktree.sh create` and `improve-reviewing`, which assume `origin/<default>` already exists.
