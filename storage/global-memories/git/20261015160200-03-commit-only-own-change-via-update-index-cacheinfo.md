---
date: 2026-10-15
keywords: ["git", "update-index", "cacheinfo", "partial-staging", "shared-checkout"]
aliases: ["commit only my change", "stage a blob without touching the worktree", "git add -p cannot split one line"]
---

## Commit only your own change in a shared single-line file by staging a blob

`git add -p` cannot split a change in a file that is one long line — a minified JSON, a lockfile:
the whole file is a single hunk. When a colleague or another agent has uncommitted work in that
same file, staging the file commits their work alongside yours.

Stage a blob instead, without touching the working tree:

```bash
git show HEAD:path/to/file > base          # the committed version
jq ... base > mine                         # base + only your change
truncate -s -1 mine                        # preserve the file's shape (e.g. no trailing newline)
sha=$(git hash-object -w mine)             # write the blob into the object store
git update-index --cacheinfo 100644 "$sha" path/to/file
git commit -m ...
```

`git update-index --cacheinfo` replaces the index entry for that path only; the working tree keeps
the other party's changes, which still show as modified afterwards. No stash or checkout dance,
so their work is never at risk. Confirm the staged result before committing with
`git diff --cached --stat` and `git show :path | jq ...`.
