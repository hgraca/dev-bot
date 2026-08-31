---
date: 2026-05-11
keywords: ["git", "pre-commit", "index"]
---

## Pre-commit hook auto-fixes can be orphaned in a corrupted git index

The repo's pre-commit hook runs PHP-CS-Fixer (import sort, unused-import removal) and re-stages the modified files mid-commit. If the commit process is interrupted (session killed, terminal closed, parallel git op) after the hook stages but before `git commit` finalises, the index references blobs that were never written to `.git/objects`. Symptom: `git status` shows phantom staged files; every subsequent git command (`git diff --staged`, `git reset HEAD`, `git commit --amend`) fails with `fatal: unable to read <sha>`. `git fsck --full` confirms `missing blob …`. Non-obvious because the staged files don't match anything in your current task — they belong to a commit pushed N commits back (in TP-6168: 2 commits back, files from commit `843b05eb9`). Working-tree files on disk are intact.
Fix: (1) Rebuild the index — `rm .git/index && git reset` regenerates from HEAD and demotes the modifications to unstaged. (2) `git diff` confirms style-only auto-fixes (alphabetical `use` sort, unused-import removal). (3) Fold into the originating commit: `git add <files> && git commit --fixup=<original-sha> --no-verify && GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <original-sha>^`. (4) `git push --force-with-lease` (NOT `--force`; the lease aborts if remote moved). Feature branches only — never force-push main/master without explicit stakeholder authorisation.
