---
date: 2026-10-30
keywords: ["git", "worktree", "relative-path", "worktree-add"]
aliases: ["worktree created in repo/repo", "git -C worktree add path"]
trigger-on: ["git-worktree-create"]
---

## `git -C <repo> worktree add <relative-path>` nests the path under the repo

`git -C "$repo" worktree add -b <branch> "$repo/.agents/worktrees/<slug>" origin/main` creates `<repo>/<repo>/.agents/worktrees/<slug>`: `-C` changes the process directory for the whole invocation, so the relative destination is resolved from inside the repo, not from the caller's cwd. Without `-C` the same path is correct, which makes the bug easy to miss in a script that builds paths from `$PWD`. Always pass an absolute destination to `worktree add` in loops over several repos, and check `git worktree list` afterwards — the branch is created even when the checkout lands somewhere unexpected.
