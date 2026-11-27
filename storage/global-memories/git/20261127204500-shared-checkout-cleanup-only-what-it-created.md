---
date: 2026-11-27
keywords: ["git", "shared-checkout", "cleanup", "index"]
aliases: ["dangling notes after publishing", "restore HEAD loses a sibling edit", "cleanup after publishing a branch"]
trigger-on: ["shared-checkout-cleanup-after-publish"]
---

## A cleanup in a shared checkout removes what it created, and nothing else

After a step publishes files to a branch, a tidy-up that clears the duplicates out of the main checkout must act only on the paths that step wrote, and must never `git restore` a tracked file to `HEAD`. Reverting a tracked file discards whatever another session has in the working tree — the checkout is shared, so that is real work rather than a stray edit — and it is unnecessary: a tracked edit stops appearing in `git status` by itself once the branch merges, so only a genuinely new file (absent from `HEAD`) creates lasting residue. For that file, compare it against the published copy first (`cmp -s`) and keep it, reported, when they differ; a note written after the publish is somebody's edit, and the published copy is on the branch if the comparison is ever wrong. Deleting the file is not enough when it was staged — the index keeps the entry and `git status` reports a pending deletion, so drop it with `git rm --cached` too. Order matters when the comparison reads the published copy out of a temporary worktree: verify before that worktree is removed, or every file compares as changed and none is ever cleaned. The window between comparing and deleting cannot be closed by a shell guard and no lock here arbitrates it, so state what it covers — edits between the publish and the cleanup — and name the recovery, `git show <branch>:<path>`.
