---
date: 2026-09-25
keywords: ["shell", "timeout", "pipe", "rebuild", "rebase"]
trigger-on: ["shell-long-running-command", "tool-timeout"]
---

## Never pipe a long-running command through `tail` while waiting for it

`cmd 2>&1 | tail -3` buffers the whole run and prints nothing until the process exits, so a job that is working perfectly looks like a hang — and if the tool wrapping the command has a timeout, that timeout kills the job mid-flight while the output being waited on never appeared. A 155-commit `git rebase` was killed twice this way and read as "hung" both times; it was progressing. Run long or watched commands in a PTY (where output streams and the tool timeout does not apply) or without the pipe, and check the real state before concluding anything — for a rebase, `test -d .git/rebase-merge` plus `pgrep -a git`. Recovery is usually free: `git rebase --abort` restored the branch exactly, verified by `git diff <base>..HEAD | git hash-object --stdin` being unchanged.
