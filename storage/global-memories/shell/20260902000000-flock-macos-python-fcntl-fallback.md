---
date: 2026-09-02
keywords: ["shell", "flock", "macos", "fcntl", "lock"]
trigger-on: ["flock-macos", "portable-lock"]
---

## flock(1) is absent on macOS — use python fcntl on the inherited fd

`flock(1)` ships with Linux's util-linux and is NOT present on stock macOS
(no /usr/bin/flock; Homebrew's util-linux is keg-only). Any script using
`exec 200>"$LOCK_FILE"; flock -n 200 || exit 0` silently no-ops on macOS: the
missing command exits 127, `|| exit 0` fires, and the intended work never
happens (fails closed, so no corruption — but graph updates / memory reindexes
never auto-run). Portable replacement that preserves exact lock semantics
(lock held on the open file description until the launching shell exits):

```bash
exec 200>"$LOCK_FILE"
{ flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 0
```

Python inherits bash's fd 200 (bash does not set CLOEXEC on `exec N>` fds), so
`fcntl.flock(200, ...)` locks the same open file description; the lock releases
when the shell exits — identical to `flock -n 200`. Do NOT use a mkdir-based
lock as a drop-in: it needs stale-lock handling (a dead process leaves the dir)
and changes release semantics. Verified: fd inheritance + release-on-exit works
on Linux; python3 is already a devbot prerequisite.
