---
date: 2026-09-18
keywords: ["git", "rebase", "history-rewrite", "verification", "reorder"]
trigger-on: ["git-reorder", "git-split-commit", "history-surgery"]
---

## Prove a history rewrite by diffing trees, not by trusting the operation

Reordering or splitting commits can be verified mechanically: after the operation `git diff <pre-rewrite-ref> HEAD` must be empty, since anything non-empty means content changed rather than just order. For a reorder, drive `git rebase -i` with `GIT_SEQUENCE_EDITOR` pointing at a script that overwrites the todo file — deterministic, no interactive editor — and expect 3-way-merge conflicts when a commit is replayed beneath its original parent; resolve the topmost commit's conflicts by taking the pre-rewrite version of each conflicted file, because its tree must end up identical. For a split by concern where files are entangled, work backwards: `git reset --mixed <base>`, revert the files belonging to the other concern, reconstruct the shared files for the first commit, commit, then `git checkout <pre-split-ref> -- .` and commit the remainder — the two commits' union must reproduce the original tree exactly.
