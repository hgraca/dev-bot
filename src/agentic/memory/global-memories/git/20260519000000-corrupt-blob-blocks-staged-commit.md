---
date: 2026-05-19
keywords: ["git", "blob corruption", "staged files", "commit error"]
---

## Corrupt blob in index blocks commit — unstage affected files first

When `git commit` fails with `error: invalid object <sha> for '<path>'` and `Error building trees`, a staged file's blob object is corrupt or missing from the object store. Running `git fsck` confirms dangling objects. Fix: `git reset HEAD <affected-files>` to unstage the corrupt entries, then stage only the files you actually want to commit. The corrupt staged files can be re-added after the object store is repaired (e.g. `git gc` or restore from remote).
