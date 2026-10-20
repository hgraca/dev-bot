---
date: 2026-10-18
keywords: ["opencode", "logging", "bash", "grep", "diagnostics"]
aliases: ["log count inflation", "permission evaluation lines", "false error count"]
trigger-on: ["opencode-log-diagnostics"]
---

## `opencode.log` records the agent's own shell commands, so a bare grep for an error phrase inflates the count

`~/.local/share/opencode/log/opencode.log` writes a `level=INFO message=evaluated permission=bash pattern="<raw command>"` line for every shell invocation, including the command string verbatim. Any `grep`/`awk`/python one-liner that searches the log for an error phrase (e.g. `prompt_async failed`, `UNIQUE constraint failed`) is itself logged on the next invocation, so the match count grows with each investigation step and the "failure rate" looks live when it is not. Count failures by filtering the log level and message instead — `grep 'level=ERROR' | grep 'message="prompt_async failed"'` — rather than the bare phrase, and prefer extracting `timestamp=`, `sessionID=` and the query params from those lines. The trap costs an incorrect intermediate conclusion whenever a failure count is used as evidence that a fix did or did not work.
