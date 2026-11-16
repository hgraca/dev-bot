---
date: 2026-11-16
keywords: ["git", "git reset", "stale tree", "rebase merge", "worktree"]
aliases: ["reset --mixed commit clobber", "branch lost its files after reset"]
trigger-on: ["dependency-bump-commit", "stale-worktree-reuse"]
---

## `git reset <upstream>` is `--mixed`: it keeps the working tree, so the next commit captures a stale tree

`git reset origin/main` (no `--hard`) moves the branch pointer and resets the index but leaves the working tree untouched. If the branch was created from a stale branch or an older commit, that working tree is still the old tree — and the next `git commit -a` / `git add -A` records the *entire* old tree as one commit whose parent is the current tip, silently reverting every commit merged in between. Nothing about the commit looks wrong: the subject says what you intended, the parent is right, and the diff is huge. A rebase-merge does not save it, because rebase replays the commit's patch faithfully — deleting files that exist in the base applies cleanly, with no conflict and no warning. Reproduced in GET-E `core` on 2026-11-16: commit `6191a041` ("chore(deps): upgrade dev-tools to 0.7.51.0") had a tree equal to the 13 Nov main tip plus the dev-tools payload, deleting three just-merged features and a pricing fix (26 files, −1665 lines); production served it for about two hours. The reflog of the throwaway branch showed the whole sequence in five seconds: `branch: Created from chore/dev-tools-0.7.50.0` → `reset: moving to origin/main` → `commit`. To move work onto main use `git rebase origin/main`; if a reset is genuinely needed, use `--hard` and re-apply the work afterwards. Cut dependency bumps from `origin/<default>` rather than stacking them on an unmerged bump branch, and treat a worktree directory whose registered branch does not match its name as a stale-tree hazard rather than a convenience.
