---
date: 2026-08-21
keywords: ["shell", "bash", "absolute-path", "cd", "symlink"]
---

## Resolve an arbitrary path to absolute portably: cd -P dirname + basename

To resolve a user-supplied path (or a symlink target) to an absolute path without `python3 -c 'os.path.realpath'` (macOS ships no python3):

```bash
abs="$(cd -P "$(dirname "$p")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$p")")" || true
```

`cd -P` resolves parent-directory symlinks and `..`; appending `basename` keeps the final component, so it handles **files** too (unlike `cd -P "$p"`, which requires a directory). It does _not_ resolve a symlink in the final component — acceptable for existence and prefix checks. Use `|| true` (or `|| abs=""`) for graceful fallback when the parent doesn't exist. Complement to the `readlink` loop (which resolves a script's _own_ path); this idiom resolves _other_ paths. Applied in dev-bot `tree.sh`, `module.sh`, and the `harnesses/*/reset.sh` scripts.
