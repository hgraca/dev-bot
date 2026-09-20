---
date: 2026-09-10
keywords: ["shell", "exec", "redirection", "stderr", "flock"]
trigger-on: ["shell-exec-redirection", "bash-fd-redirect"]
---

## `exec fd>file 2>/dev/null` permanently redirects the shell's stderr

In bash, `exec` with only redirections applies them to the current shell and they persist for the rest of the process. So `exec 200>"$lockfile" 2>/dev/null` does not just open fd 200 — it also permanently points fd 2 at `/dev/null`, silently swallowing every later `echo … >&2` and any `_error`/`_fatal` helper that writes to stderr. The fix is to scope the suppression to a group: `{ exec 200>"$lockfile"; } 2>/dev/null` — fd 200 still persists, fd 2 is restored after the group. This bit `_devbot_lock_wait` in `src/_shared/functions.sh`: calling it early (e.g. from `bin/update.sh` before the error paths) hid all subsequent error output, which is how a `devbot update <bad-tag>` stopped printing "does not exist".
