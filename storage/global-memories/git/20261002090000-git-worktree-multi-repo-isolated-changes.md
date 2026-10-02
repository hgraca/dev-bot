---
date: 2026-10-02
keywords: ["git", "worktree", "multi-repo", "branch-isolation"]
trigger-on: ["multi-repo-change", "sibling-repo-batch-edit"]
---

## Isolate a change across many sibling repos with one git worktree each

When the same change must land in several sibling repos that are each on an unrelated branch with a dirty working tree, create a throwaway worktree per repo off the default branch instead of switching branches in place: `git -C <repo> fetch origin <default>` then `git -C <repo> worktree add --no-track -b <branch> /tmp/.../<repo> origin/<default>`. `--no-track` keeps the new branch from adopting `origin/<default>` as upstream. Edit, commit, push and open the PR inside the worktree, then `git -C <repo> worktree remove --force <path>`. This never touches the repo's current branch or uncommitted files and sidesteps the "dirty tree blocks checkout" failure entirely. The local branch survives worktree removal, so the PR head remains checkable.
