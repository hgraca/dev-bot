---
date: 2026-11-25
keywords: ["git", "commit", "pathspec", "index"]
aliases: ["git commit -- path ignores staged hunks", "fixup commit swallowed the whole file"]
---

## `git commit -- <path>` commits the working tree, not the index

Passing a pathspec to `git commit` (`git commit --fixup <sha> -- src/file`) does not honour the staging area: git commits the **current working-tree contents** of those paths, exactly as `git commit -a` would for them. Careful hunk staging done with `git add -p`, `git apply --cached`, or `git restore --staged` is silently discarded, so a commit meant to carry one hunk captures every pending change in that file — which is how a `--fixup` intended for one commit ends up holding three unrelated hunks.

To commit exactly what is staged, run `git commit` with **no** pathspec and verify with `git show --stat HEAD`. The pathspec form is right only when you deliberately want the whole file, or when isolating your work from another agent's staged entries — and then the `--stat` check is mandatory. Recovering a mis-made unpushed commit is `git reset --soft HEAD~1 && git reset`, which leaves the working tree untouched.
