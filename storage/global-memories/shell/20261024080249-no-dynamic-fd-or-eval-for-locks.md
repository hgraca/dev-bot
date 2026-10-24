---
date: 2026-10-24
keywords: ["shell", "bash", "flock", "descriptors"]
---

## Holding two flock locks in one script: no `eval`, no `exec {var}>`

A helper that opens a lock on a fixed descriptor (`exec 200>file`) cannot be reused for a second, independent lock in the same script — the nested call replaces the first lock on that fd and silently releases it (a boot script that holds its own lock and then takes a session-registry lock is exactly this case).

Two tempting fixes are both wrong:

- `eval "exec ${fd}>\"${lockfile}\""` — the lock path derives from `DEV_BOT_ROOT` / runtime dirs, so a checkout or override named `$(touch /tmp/pwned)` executes on the way to locking.
- `exec {var}>"${lockfile}"` — dynamic descriptor allocation is bash 4+, while dev-bot's helpers stay compatible with macOS's bash 3.2.

What works: split the helper in two. The caller opens its own descriptor with a **literal** number (`exec 201>"${file}"`, distinct from the other holder's 200), and a shared `_devbot_lock_acquire <fd> <cap> <msg>` does the waiting — `flock -n "$fd"` takes the number as an argument, which 3.2 handles. The kernel releases both on exit, including SIGKILL, so nothing needs closing.

Cost of getting it wrong: one review round on a PR (first the eval/injection, then the bash-4 construct).
