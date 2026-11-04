---
date: 2026-11-04
keywords: ["git", "squash", "fixup", "rebase", "reset"]
aliases: ["rebase refuses dirty worktree", "squash without rebase -i", "autosquash fails uncommitted changes"]
---

## Squash fixups without `rebase -i` when the worktree has uncommitted changes

`git rebase -i --autosquash <base>` refuses to start with "cannot rebase: You have unstaged
changes" — routine in a worktree whose dev tooling rewrote tracked files (`Makefile`, `scripts/*`,
`.env*`) that must not be committed. `git reset --soft <feature-commit>~1` moves HEAD back to the
parent while leaving the index untouched, so the fixups collapse into the index exactly as they
were: `git reset --soft <base> && git commit -F <original-message>` produces one commit with an
identical tree (verify with `git rev-parse HEAD^{tree}` before and after) and leaves the unrelated
dirty files unstaged.

This is a history rewrite on a pushed branch — only after the user approves, and the human
publishes it with `git push --force-with-lease=refs/heads/<branch>:<old-remote-sha>`. Guard first:
compare `git ls-remote origin refs/heads/<branch>` with `git rev-parse HEAD` and refuse when they
differ, so another push is never overwritten.
