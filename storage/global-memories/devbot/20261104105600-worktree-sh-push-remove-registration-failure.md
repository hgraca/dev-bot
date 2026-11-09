---
date: 2026-11-04
keywords: ["devbot", "worktree", "worktree.sh", "monorepo"]
aliases: ["no worktree is registered", "worktree.sh push fails", "worktree.sh remove fails"]
---

## `worktree.sh push` and `remove` cannot find a registered worktree in a monorepo session

With `--project <owner>` passed exactly as documented, `worktree.sh create` and
`worktree.sh path <branch>` resolve the worktree correctly, but `worktree.sh push <branch>
--project <owner>` and `worktree.sh remove <branch> --project <owner>` both fail with
`FATAL: push|remove: no worktree is registered for '<branch>'`. The registration exists
(`git -C <owner> worktree list` shows it), so those subcommands' lookup disagrees with `path`'s.

Workaround, equivalent to what the tool does: push with
`git -C <worktree> push -u origin <branch>`, and remove with
`git worktree remove <absolute worktree path>` (absolute; a relative path fails with
`is not a working tree`). Teardown still needs the manual steps the tool does not cover: `make down`
in the worktree, `docker rm` containers left under an earlier project name, drop the MariaDB and
Mongo databases named after the worktree slug (including the `_phpunit`/`_dusk` and paratest
`_phpunit_N` copies), and remove the hosts entry with `scripts/ensure-hosts.sh --remove <host>`.
