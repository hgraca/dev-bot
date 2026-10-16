---
date: 2026-10-16
keywords: ["git", "rebase", "squash", "shared-checkout"]
---

## Squashing your own commits when a shared checkout interleaves others'

In a shared checkout another session's commits can land **between** yours, leaving your commits non-contiguous. `git rebase -i <base>` replays every commit in the range — including the foreign ones — rewriting their SHAs even when their content is byte-identical. To fold your own commits without touching another session's work, rebase from the **parent of your first commit** (`git rebase -i --autosquash <last-foreign-sha>`), so the range holds your contiguous block alone; the foreign commits stay below and keep their SHAs. Record corrections first with `git commit --fixup=<target>`, then autosquash non-interactively with `GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true`. Verify afterwards: `git diff <pre-rebase-HEAD> HEAD` is empty (content preserved), and the foreign commits' SHAs are unchanged.
