---
date: 2026-10-22
keywords: ["git", "autosquash", "fixup", "rebase"]
aliases: ["fixup! conflict", "deleted by us during autosquash", "autosquash ordering"]
trigger-on: ["git-fixup-commits", "git-autosquash"]
---

## An autosquash fixup must target the commit that introduces every file it touches

`git commit --fixup=<sha>` records a diff against the current HEAD, but `rebase --autosquash`
replays that diff **at the target commit**. If the fixup touches a file (or hunk context) that a
*Later* commit introduces, the replay has nothing to patch: the rebase stops with a "deleted by us"
conflict, because at that point in the rewritten history the file does not exist yet. This bites
when review corrections are collected into one fixup that edits both a feature file and a test file
added by a separate, later test commit.

Split the correction by target before squashing: file-introducing commit for edits to files added
later, feature commit for its own files. Preview the plan without executing it —
`GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <base>` — and check that
each `fixup` line sits under the commit whose tree already contains its files.

When a conflict does occur mid-rebase, resolving by keeping the incoming block and deferring the
part that belongs to the later target works, but the real proof is content equality after the
rewrite: compare `git rev-parse HEAD^{tree}` and `git diff <base>..HEAD | git hash-object --stdin`
before and after. Identical values mean the squash reorganized history without altering a byte.
