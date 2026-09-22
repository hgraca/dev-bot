---
date: 2026-09-22
keywords: ["shell", "bash", "exit-status", "command-substitution"]
trigger-on: ["shell-capture-exit-status", "log-rc-line", "command-substitution-in-message"]
---

## A command substitution elsewhere in the line resets `$?` before you read it

`echo "[$(date -u +%H:%M:%S)] finished rc=$?"` always prints `rc=0`. Bash expands `$(date)` while building the arguments, and running the substitution sets `$?` to `date`'s status — so the exit code of the command you actually meant to report is gone before the expansion reaches `$?`. Assign it first (`cmd; rc=$?`), then build any message from `$rc`. The bug survives review because the line _looks_ like it reports the status, and a test asserting `rc=0` passes vacuously — which is how it was found: a new test asserting `rc=1` failed while the log showed the error message and `rc=0`. Rule: whenever a command's exit code is the thing being reported, capture it before any other expansion in the same line.
