---
date: 2026-11-22
keywords: ["worktree", "worktree.sh", "probe", "gh", "cwd"]
---

## `worktree.sh path` is not an emptiness probe, and every worktree probe is cwd-scoped

`worktree.sh path <branch>` exits `FATAL: no worktree is registered for '<branch>'` when nothing is registered — it is a resolver, not a check, so an "if this is empty, create" flow fails on its own first run. Probe with `worktree.sh list` (one `<path> <branch>` line per worktree) and test the branch with `git rev-parse --verify --quiet`. The same tooling and `gh` both take the repository from the **working directory**: run them from the project's main checkout (`cd "$root"`), or from a consumer project they silently answer for the consumer's repository. `create` also refuses an existing branch or path, so a resumed task must reuse or attach the branch (`git worktree add <abs-path> <branch>`) rather than cut a new one.
