---
date: 2026-10-13
keywords: ["devbot", "worktree", "cwd", "worktree-remove"]
trigger-on: ["devbot-worktree-remove", "worktree-remove-wrong-repo"]
---

## `worktree.sh remove` resolves the path against the caller's repo — run it from the right checkout

`worktree.sh remove <branch>` derives the worktree directory as `<repo>/.agents/worktrees/<branch-with-slashes-as-dashes>`, where `<repo>` is the repository of the **current working directory** — not the repo that owns the branch. Invoke it from another project's checkout (an agent shell whose default cwd is a different project) and it fails with `FATAL: remove: no worktree at <other-repo>/.agents/worktrees/<slug>`, leaving the worktree in place and the follow-up `git branch -D` blocked by `cannot delete branch '<b>' used by worktree at …`. Always run it with the target repo as the cwd (a `workdir=`/`cd` into that repo), then delete the branch — the branch is safe to force-delete once its content is confirmed present on the default branch.
