---
date: 2026-11-25
keywords: ["shell", "pkill", "process", "signal"]
aliases: ["pkill killed my own shell", "exit code 143", "pgrep self-match"]
---

## `pkill -f <pattern>` kills the shell that runs it

`pkill -f 'remote-debugging-port=9333'` matched the wrapping `bash -c` command line, which contains that same string, so the shell died before `pkill` returned — exit 143 (SIGTERM), no output, and every command chained after it never ran. Kill by something that cannot name the caller: a pid file, `lsof -ti :<port> | xargs kill`, or a pattern built at runtime so the literal never appears in the invoking command line. The same self-match hits `pgrep -f` and any `-f` match whose string is visible in the current process's arguments.
