---
date: 2026-05-17
keywords: ["git", "corrupt blob", "index", "missing object", "staging"]
---

## Fix corrupt staged blob with `git rm --cached` + re-add

When `git commit` fails with `error: invalid object <hash> for '<file>'` and `git fsck` reports `missing blob <hash>`, the git index references a blob that no longer exists in the object store. Fix: `git rm --cached <file>` (removes the corrupt index entry without touching the working tree), then `git add <file>` (re-hashes the file from disk and writes a fresh blob). The commit then succeeds. This can happen after interrupted writes, filesystem corruption, or partial object transfers. Do not attempt `git commit --amend` or force-push to fix — the blob is simply missing from the local store and must be re-created from the working tree copy.
