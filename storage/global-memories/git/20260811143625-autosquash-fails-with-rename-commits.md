---
date: 2026-08-11
keywords: ["git", "autosquash", "rebase", "fixup", "rename"]
trigger-on: ["git-autosquash", "git-fixup-collapse", "git-rename-conflict"]
---

## git rebase --autosquash fails when fixups target pre-rename files

When a branch has fixup commits targeting files that were later renamed, `git rebase -i --autosquash` fails with modify/delete or rename/delete conflicts. Autosquash applies commits in chronological order, so fixups for pre-rename file paths arrive before the rename commits that changed those paths. The fixup tries to patch a file at its old path, which no longer matches the renamed content. The reliable workaround is `git merge --squash` to collapse the entire branch into a single clean commit, discarding the fixup markers. Use `git diff <old-branch> <new-branch> --stat` to verify the trees are identical.
