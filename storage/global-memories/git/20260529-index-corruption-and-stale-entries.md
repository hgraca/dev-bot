---
tags: [git, index, corruption, gotcha]
description: Pre-existing stale index entries from deleted files cause repeated commit failures. Use `git rm --cached <path>` per corrupt file. Add `git fsck` pre-check before commits.
---

## Git Index Corruption from Stale Entries

### Problem

When a prior session creates and tracks files that are later deleted (or a session crashes mid-commit), stale git index entries persist. Attempting `git add` + `git commit` produces:

```
error: invalid object 100644 <sha> for '<path>'
error: Error building trees
```

The object pointed to by the index no longer exists in the object store.

### Recovery

```
git rm --cached <corrupt-path>
git add <file-to-commit>
git commit -m "..."
```

Repeat for each corrupt path found in the error message.

### Prevention

- Before starting a session with many file operations, run `git fsck 2>&1 | grep "invalid sha1 pointer"` to detect stale index entries.
- After any session that creates+deletes tracked files, run `git gc --prune=now` to clean the object store.
- Do not use `git add -A` or `git add .` in repos with stale entries — always use `git add <specific-files>`.

### Experience

During the codebase-index module implementation (2026-05-29), 6 of 8 commit attempts failed due to stale index entries from prior sessions (qmd module, watermark-session module, format-md test tmpdirs). Each failure required individual `git rm --cached` recovery.
