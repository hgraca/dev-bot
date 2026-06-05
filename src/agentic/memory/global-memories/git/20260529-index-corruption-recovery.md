---
date: 2026-05-29
keywords: ["git", "index", "cache-tree", "corruption", "invalid object"]
---

## Git index recovery when commit fails with "invalid object" and "Error building trees"

When git commit fails with `error: invalid object <sha> for '<path>'` followed by `error: Error building trees`, the working tree and blob objects are usually intact — the cache-tree in `.git/index` is stale. This happens when files are created, staged, and committed across multiple agent sessions, and the cache-tree pointers to stale tree objects persist in the index.

Recovery: `rm -f .git/index && git reset HEAD -- .` — this deletes the stale index (including its corrupt cache-tree) and rebuilds it from HEAD. All staged changes are lost (but can be re-staged). Use `rm -f` because `git reset` alone does not rewrite the cache-tree. Run `git write-tree` afterward to confirm success.

Prevention: Run `git fsck` before committing after creating files across multiple delegations, especially when files were committed in a prior session.
