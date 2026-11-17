---
date: 2026-11-15
keywords: ["git", "pathspec", "commit", "rm --cached"]
aliases: ["git commit -- file", "partial commit takes working tree", "untrack files"]
trigger-on: ["git-untrack-files", "git-partial-commit"]
---

## `git commit -- <pathspec>` commits the working tree, not the index

Running `git rm -r --cached <path>` and then `git commit -m … -- <path>` silently re-adds the files: with a pathspec git builds the commit from the working-tree content of those paths and ignores what the index holds, so the untracking is a no-op and the index is left matching HEAD. The commit reports success and its message lies. Correct: stage with `git rm --cached`, confirm with `git diff --cached --name-status`, then `git commit` with no pathspec. Symptoms of getting it wrong: the commit stat lists only the other files, `git status` is clean, and `git ls-files` still lists the paths you thought you removed. When the commit is local and unpushed, `git reset --soft HEAD~1` and redo it rather than layering a correction on top.
