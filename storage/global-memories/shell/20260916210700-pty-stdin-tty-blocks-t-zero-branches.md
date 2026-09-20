---
date: 2026-09-16
keywords: ["shell", "pty", "tty", "stdin", "isatty"]
trigger-on: ["pty-stdin-tty", "shell-t-zero-guard"]
---

## Running a test suite inside a PTY makes stdin a tty, so `[ -t 0 ]` branches block forever on `read`

A PTY session gives the child a **tty on stdin**, which silently flips every "am I interactive?" guard the other way. A suite that branches on `[ -t 0 ]` (or `SKIP_CONFIRM`) and otherwise calls `read` will take the interactive path and **hang with no output**, looking exactly like a slow or stuck suite — one test sat 8 minutes at 0% CPU before the cause was found. Diagnose by reading the blocked process's stdin: `readlink /proc/<pid>/fd/0` showing `/dev/pts/N` is the tell (a normal non-interactive shell shows `/dev/null`). Fix: **wire stdin from `/dev/null`** for anything non-interactive — `make test </dev/null` — even inside a PTY. Redirecting *stdin* is right; redirecting *stdout* is what hides a run from the PTY's own output view. Practical corollary when using a background-PTY tool: a command that legitimately exceeds a blocking tool timeout belongs in a PTY, but one that prompts does not — and this repo's suite is in the first category only if stdin is rerouted.
