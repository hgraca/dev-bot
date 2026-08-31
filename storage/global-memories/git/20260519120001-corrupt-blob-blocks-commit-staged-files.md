---
date: 2026-05-19
keywords: ["git", "blob", "corruption", "staging"]
---

## Corrupt blob blocks commit when agent files staged from prior session

If `git commit` fails with `error: invalid object <sha> for '<file>'` and `error: Error building trees`, a staged file references a corrupt or missing blob object. Cause: prior session staged a file whose blob was never fully written (e.g. interrupted write, cross-session staging). Fix: `git reset HEAD <affected-files>` to unstage the corrupt entries, then stage only the files from the current session and commit. The corrupt staged entries are safe to drop — the working-tree files are intact. Verify with `git fsck --lost-found` to confirm the blob is dangling, not referenced by any reachable commit.
