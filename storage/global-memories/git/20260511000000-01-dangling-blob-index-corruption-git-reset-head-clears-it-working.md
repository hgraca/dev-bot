---
date: 2026-05-11
keywords: ["git", "commit", "blob", "corruption"]
---

## Dangling-blob index corruption: `git reset HEAD` clears it, working tree survives

After an interrupted/aborted tool sequence, the index can hold an entry pointing to a blob OID that does not exist in `.git/objects/`. Symptom: `git commit` hangs indefinitely (no output, no error, no timeout), or aborts with `error: invalid object`. `git fsck` reports `missing blob <oid>` for the path. Distinct from the [[Stale staged blobs survive across `write` tool calls]] case — there the blob simply has wrong content; here the blob is entirely absent from the object store. HEAD remains valid; only the index is corrupted.
Fix: `git reset HEAD` (no path arg) clears the entire index back to HEAD, dropping the dangling reference without touching the working tree. Re-stage from disk with explicit paths, then commit. Hit on 2026-05-11 while addressing tester.md permission edits: bad blob `4cf5fa4…` referenced in index, HEAD had valid `445e0a2…`, `git reset HEAD` recovered cleanly. `git fsck` post-reset showed only harmless dangling commits/blobs. See [[patterns]] for git commit workflow.
