---
date: 2026-10-21
keywords: ["git", "autosquash", "fixup", "rebase"]
aliases: ["autosquash conflict", "fixup conflicts on rebase", "mixed fixup commit"]
trigger-on: ["git-autosquash-fixups"]
---

## A fixup that mixes files from two target commits conflicts on autosquash

`git rebase -i --autosquash` applies each `fixup!` as a patch on top of its target. When one fixup changes files introduced by two different commits — e.g. a workflow correction that edits both `tools/worktree.sh` (from the feature commit) and `skills/git-worktrees/SKILL.md` (from a later docs commit), but is recorded with `--fixup=<feature commit>` — the hunk for the file that does not exist at the target point cannot apply and the rebase stops with a conflict.

Symptom: the autosquash plan looks correct and the fixups are in commit order, yet the rebase fails on the first fixup for that target. `git rebase --abort`, then inspect `git diff --stat <last-base>..HEAD`: a file whose introducing commit differs from the fixup target is misrouted.

Fix: split the fixup by owning commit before squashing — one `git commit --fixup=<target>` per file group, each holding only files that the target introduced. Autosquash then applies cleanly. Verify the rewrite preserved content with `git rev-parse HEAD^{tree}` before and after; an autosquash must not change the tree.
