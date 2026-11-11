---
date: 2026-11-11
keywords: ["git", "autosquash", "rebase", "theirs"]
see: ["learnings/20261102205200-autosquash-diff-hash-check-base-moved.md"]
---

# `rebase --autosquash -X theirs` can change the tree silently

When `git rebase -i --autosquash` stops on a conflict while folding fixups into their target, `--strategy-option=theirs` looks like the right resolution: the fixup carries the newest content. It is not. `theirs` applies to **every** conflicting hunk of that step, including hunks where the base commit's content was correct and the fixup never touched them, so the resulting tree silently loses base content. The failure is invisible — the rebase reports success and `git log` looks right; only comparing `git rev-parse HEAD^{tree}` before and after reveals it.

Resolve per file instead: keep the pre-rebase head sha, and at each stop run `git checkout <sha> -- <path>` for every path in `git diff --name-only --diff-filter=U`, then `git add` and continue, looping while the rebase-merge directory exists. The final tree must hash identically to the pre-rebase tree; a mismatch means something was lost.
