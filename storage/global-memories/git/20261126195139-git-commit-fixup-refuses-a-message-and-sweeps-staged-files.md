---
date: 2026-11-26
keywords: ["git", "fixup", "autosquash", "staging"]
aliases: ["fixup cannot take -F", "fixup swallows staged files"]
trigger-on: ["git-fixup-commits"]
---

## git commit --fixup refuses a message, and it sweeps up whatever is staged

`git commit --fixup=<sha>` rejects `-F` and `-m` outright (`fatal: options '-F' and '--fixup' cannot be used together`), so a fixup cannot carry the repo's Problems/Solutions body — git writes that message itself, which is why fixups are exempt from message rules. The second trap is staging: an edit staged for a commit that then failed stays staged, so the next `git commit --fixup` folds those unrelated files into that fixup. Verify with `git log --oneline --name-only origin/main..HEAD` after `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main`; to re-split, `git reset --soft HEAD~1`, `git restore --staged <other files>`, then commit each fixup against its own target.
