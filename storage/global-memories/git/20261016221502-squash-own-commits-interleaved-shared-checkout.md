---
date: 2026-10-16
keywords: ["git", "rebase", "squash", "shared-checkout"]
---

## Squashing your own commits when a shared checkout interleaves others'

In a shared checkout another session's commits can land **between** yours, leaving your commits non-contiguous. `git rebase -i <base>` replays every commit in the range — including the foreign ones — rewriting their SHAs even when their content is byte-identical.

Only a **contiguous tail above the foreign commits** is safe to autosquash: rebase from the parent of your first commit (`git rebase -i --autosquash <last-foreign-sha>`), so the range holds your block alone and the foreign commits below keep their SHAs. If your commits are **interleaved** with foreign ones, there is no such base — do **not** rewrite that history. Ask the other session for approval, or land the correction as a follow-up commit.

Record corrections first with `git commit --fixup=<target>`, then autosquash non-interactively with `GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true`. Verify afterwards: `git diff <pre-rebase-HEAD> HEAD` is empty (content preserved), and the foreign commits' SHAs are unchanged.
