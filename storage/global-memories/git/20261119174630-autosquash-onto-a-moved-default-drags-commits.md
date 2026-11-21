---
date: 2026-11-19
keywords: ["git", "rebase-autosquash", "fixup", "origin-main", "squash"]
aliases: ["autosquash landed on a newer base", "squash changed the tree", "DU conflict on a file a fixup adds"]
trigger-on: ["git-autosquash", "fixup-squash"]
---

## `rebase -i --autosquash origin/<default>` re-bases onto the _current_ default, not the branch's base

Folding fixups with `git rebase -i --autosquash origin/main` after a `git fetch origin main` replays the branch onto the newly moved default. The rebase reports success, `git log` looks clean, and the tree silently changes — the branch now carries upstream commits, which on a pull request means a fresh CI cycle and possibly a dismissed approval. Compare `git rev-parse HEAD^{tree}` before and after; when it differs, restore the tested tree with `git rebase --onto <old-base> <new-base>` (move the squashed commit back onto the base the checks actually ran against). Only refresh the base deliberately, then re-run CI.

**Fixups must target the commit that could apply them.** A fixup whose payload edits a file created by a _later_ commit in the branch cannot autosquash into an earlier one; the rebase stops with `DU <file>` (deleted by us, updated by them) and leaves a half-squashed `# This is a combination of 2 commits` head. Split the fixup by file and target each one correctly (`git reset --soft HEAD~1`, then one `--fixup=<sha>` per file).
