---
date: 2026-09-30
keywords: ["shell", "flock", "locking", "race-condition"]
trigger-on: ["flock-session-registry", "lock-free-probe-prune"]
---

## A lock-free reader must never prune the flock registry it reads

A liveness registry built on `flock` has a two-step registration: the process **creates** its file (`exec 210>session-$$`), then **locks** it (`flock -x 210`). A prober that treats "I can lock this file → no holder → stale" as licence to `rm` it can fire inside that window: it unlinks the file the registrant just opened, the registrant then locks an **unlinked inode**, and its name never reappears. That session is lost from the registry **permanently** — not merely for one pass — so the "self-correcting" framing is wrong.

Consequences worth designing around:

- Prune only from a caller that holds the registry lock, and have the registrant hold that same lock across create **and** lock. Pass an explicit opt-in (`_devbot_live_session_files --prune`) rather than pruning by default, so a future lock-free caller cannot re-introduce the hazard.
- A child invoked from inside the lock must be told (`_DEVBOT_REGISTRY_LOCK_HELD=1`), or it re-opens the same directory and blocks forever on an `flock` it can never get — `flock` is per open file description, so a second `open` in the same process is a deadlock, not a no-op.
- Reading a registry and mutating it are different permissions. A read-only probe should be a pure function of the filesystem.
