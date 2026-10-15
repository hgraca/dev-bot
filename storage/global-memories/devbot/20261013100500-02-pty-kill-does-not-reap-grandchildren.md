---
date: 2026-10-13
keywords: ["devbot", "pty", "pty_kill", "process"]
aliases: ["make target still running after pty_kill", "Address already in use after stopping the server"]
trigger-on: ["devbot-pty", "long-running-server"]
---

## `pty_kill` does not reap a PTY command's grandchildren — long-running servers survive it

Killing a PTY session stops the shell but not the process tree beneath it. A `make storybook` target that ends in `python3 -m http.server` leaves **both** the `make` process and the python server alive after `pty_kill`, silently holding the port. The next run of the same target then fails with `OSError: [Errno 98] Address already in use`, minutes or hours later, with no obvious connection to the earlier session.

Always follow a PTY kill of a long-running command with an explicit PID sweep, and kill by PID rather than by pattern:

```bash
PIDS=$(ps -eo pid,cmd | grep -E 'python3 -m htt[p]\.server|<unique-cmd>' | awk '{print $1}')
[ -n "$PIDS" ] && kill $PIDS
```

Bracket one character in the grep pattern (`htt[p]`) so the pattern does not match the grep process itself — and never use `pkill -f` with a pattern that appears in your own command line, since it matches and kills its own shell.
