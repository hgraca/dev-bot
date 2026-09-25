---
date: 2026-09-25
keywords: ["git", "git-mv", "staging", "atomic-commits"]
trigger-on: ["git-mv-staged-rename"]
---

## `git mv` stages the rename — a later pathspec-less commit sweeps it in

`git mv` updates the index immediately, so the rename is staged the moment it runs. A subsequent `git commit` with no pathspec commits **everything** staged, including that rename — how a move meant for a feature commit landed inside an unrelated `docs(memory):` commit, leaving a broken intermediate state (the renamed script still pointed at its old sibling path). `git status` right before the commit shows `R  old -> new` and is the tell. Fix/workaround: after `git mv`, either commit the move immediately, or `git restore --staged <paths>` before the next commit, or always commit with an explicit pathspec (`git commit <files>`) rather than a bare `git commit`.
