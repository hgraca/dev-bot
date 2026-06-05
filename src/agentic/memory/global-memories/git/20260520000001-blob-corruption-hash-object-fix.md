---
date: 2026-05-20
keywords: ["git", "blob corruption", "missing object", "hash-object", "staging"]
---

## Git blob corruption requires `git hash-object -w` before staging affected files

When `git add` or `git commit` fails with `error: invalid object ... for '<file>'` and `error: Error building trees`, the git object store has a missing or corrupt blob for that file. Running `git hash-object -w <file>` re-registers the file's content as a new blob in the object store, after which `git add` and `git commit` succeed normally. Each affected file must be re-hashed individually — the error message names the file. This can happen after filesystem-level operations (e.g. ecryptfs remounts, interrupted writes) that corrupt the `.git/objects/` pack. `git fsck` will show the missing blob as `missing blob <sha>`.
