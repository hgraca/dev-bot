---
date: 2026-11-16
keywords: ["git", "fixup", "rebase-merge", "branch"]
aliases: ["fixup after merge", "commits landed on main", "merged branch SHAs rewritten"]
see: ["ADRs/20261024022740-pr-stage-fixups-and-memory-commits.md"]
---

# After a rebase-merge the branch's SHAs are new — a fixup made then lands on main

A rebase-merge rewrites every commit of the PR, so the SHA you recorded as a `--fixup` target before the merge no longer identifies the code on the default branch (and the remote head branch is deleted). If the checkout has since moved to `main`, `git commit --fixup=<old-sha>` fails to find its target in the rebase range and simply commits a `fixup!` **on main**, which can never be folded — while `git rebase -i --autosquash origin/main` afterwards is a no-op for it, because the target lies outside the range.

The trap looks like success: the commit is created, the tree is right, and the rebase reports success. Check `git status -sb` before committing a correction: if the branch is `main`, the correction is a normal follow-up commit on a **new branch**, never a fixup. Recover by cherry-picking the fixup commits onto a fresh branch off `origin/main`, rewording them, and restoring `main` to `origin/main`.
