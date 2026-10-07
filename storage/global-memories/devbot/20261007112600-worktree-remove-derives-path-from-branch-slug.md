---
date: 2026-10-07
keywords: ["devbot", "worktree", "git"]
aliases: ["worktree remove fails", "worktree custom path"]
trigger-on: ["devbot-worktree-remove"]
---

## `worktree.sh remove <branch>` cannot remove a worktree added at a custom path

`worktree.sh remove <branch>` derives the worktree directory from the branch slug — `<repo>/.agents/worktrees/<branch-with-slashes-as-dashes>` — and refuses with `FATAL: remove: no worktree at …` when the directory does not match that name. A worktree added manually for an existing branch (e.g. `git worktree add .agents/worktrees/pr-173 <branch>`, the way to work an existing PR branch, since `create` refuses existing branches) therefore cannot be removed by the tool. Remove it with raw git instead: `git worktree remove .agents/worktrees/pr-173`, adding `--force` only if it refuses on untracked/ignored content. The branch ref is kept by either path — delete it separately (`git branch -D`) once its content is confirmed present in the default branch.
