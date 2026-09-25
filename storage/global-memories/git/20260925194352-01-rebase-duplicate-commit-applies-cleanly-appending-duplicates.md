---
date: 2026-09-25
keywords: ["git", "rebase", "patch-id", "range-diff", "duplicate"]
trigger-on: ["git-rebase-stacked-branch", "git-rebase-clean-apply-duplicate"]
---

## A rebased duplicate commit can apply cleanly by appending duplicates — no conflict marker

When a stale branch is rebased onto a parent whose history was itself rebased, its already-applied commits are often **not** dropped: git's automatic skip uses `git patch-id`, and a base move changes surrounding context and hunk headers, so the patch-ids no longer match. Most such duplicates then conflict loudly — but the dangerous case is one that applies **cleanly**, e.g. a commit whose only surviving effect is appending a block to the end of a large file. Git reports success with no conflict, yet the file now holds a byte-identical second copy of code that already exists (on one branch: five identical test methods, which PHP would fatal on as a redeclare). Catch it after any rebase onto a rebased parent by looking for a commit with `+N insertions, 0 deletions` into an existing large file, by running `git range-diff <old-base>..<old-tip> <new-base>..<new-tip>` (a `!` row whose diff is mostly `-` lines is this pattern), and by grepping the touched files for duplicate symbol/method names. When the duplicate is fully redundant, `git rebase --onto <new-base> <dup-sha> HEAD` drops just it — note that passing `HEAD` explicitly detaches the repo, so re-attach with `git checkout -B <branch>`.
