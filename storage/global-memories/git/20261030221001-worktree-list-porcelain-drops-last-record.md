---
date: 2026-10-30
keywords: ["git", "worktree", "porcelain", "awk"]
aliases: ["worktree list drop-last", "porcelain record separator"]
trigger-on: ["git-worktree-list-parsing"]
---

## `git worktree list --porcelain` separates records but never flushes the last one

Porcelain output puts a blank line _between_ worktree records and no blank line _after_ the final record, so a `while IFS= read -r line` loop that emits a record on `^$` silently drops the last worktree — usually the one you just created. Every parser must flush on end of input as well: `awk … END { if (path != "") print path, branch }`, or append a newline before reading. The same shape explains a lookup that reports `no worktree is registered` for a worktree `git worktree list` plainly shows.
