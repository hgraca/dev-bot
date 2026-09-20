---
date: 2026-09-20
keywords: ["git", "git-rm", "empty-directories"]
---

## `git rm` prunes the directories its last tracked file leaves empty

Deleting a directory's contents with `git rm <files>` also removes the now-empty parent directories from the working tree — git does not leave them behind for you to clean up. Expecting empty directories to linger, and then hunting for them or reaching for a recursive delete that a guard may block, is wasted effort: once every file under a directory has been `git rm`-ed, `[ -d <dir> ]` is already false. The same applies when a `git rm -r` or a checkout empties a subtree.
