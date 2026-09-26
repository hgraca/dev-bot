---
date: 2026-09-26
keywords: ["shell", "pkill", "process-management"]
trigger-on: ["pkill-f-self-match"]
---

## `pkill -f <pattern>` kills the shell that ran it

`pkill -f` matches against the full command line of every process — including the shell executing the command, whose command line contains the pattern verbatim. `pkill -f "python.*server.py.*18777"` therefore kills its own shell: the tool call hangs until its timeout, and any command chained after it never runs, with no output explaining why. Match on something the invoking command line cannot contain (a PID from `pgrep`, from `$!`, or an anchored path like `^/usr/bin/python`), or kill by recorded PID. Never place a `pkill -f` last in an `&&` chain whose earlier steps matter, and prefer to skip the kill entirely when the process was already cleaned up.
