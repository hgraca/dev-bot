---
date: 2026-11-18
keywords: ["git", "concurrent", "index", "commit-tree", "update-ref"]
---

## Two agents in one checkout share .git/index — land commits with a private index and a CAS ref update

When two sessions work in the same checkout, `git commit` takes the whole index: one agent's `git add` can ride into another agent's commit under the wrong message, and a later `commit --amend`, reset or rebase from that agent can drop the first agent's commit from the branch. The commit object survives (`git cat-file -t <sha>` still answers), so the work is recoverable, but the history is not what either agent intended. To land a commit without racing the shared index: build it with a private index (`GIT_INDEX_FILE=/tmp/idx git read-tree HEAD`, then stage only through that file — `git update-index --cacheinfo` for a file whose working-tree copy contains someone else's edits), write the tree (`GIT_INDEX_FILE=/tmp/idx git write-tree`), create the commit (`git commit-tree "$tree" -p HEAD -F msg`), and publish atomically with `git update-ref refs/heads/<branch> "$new" "$(git rev-parse HEAD)"` — the old-value argument turns a concurrent move into a failure instead of a lost commit. Afterwards clear your own leftovers from the shared index (`git reset HEAD -- <paths>`), or the next commit there inherits them. Check `git branch -r --contains <sha>` before amending: no output means the commit is local-only and safe to rewrite.
