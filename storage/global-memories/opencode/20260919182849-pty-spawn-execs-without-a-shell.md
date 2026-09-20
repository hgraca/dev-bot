---
date: 2026-09-19
keywords: ["opencode", "pty", "pty_spawn", "shell", "redirect"]
trigger-on: ["opencode-pty-spawn", "pty-shell-syntax"]
---

## `pty_spawn` execs the program directly — there is no shell, so shell syntax must be wrapped

`pty_spawn({command, args})` passes the executable and its argument array straight to the process spawn (opencode-pty's `manager.spawn`, backed by `bun-pty`); nothing interprets the arguments. `pty_spawn(command: "make", args: ["test", "</dev/null"])` therefore hands `make` the literal argument `</dev/null` and the redirect never happens — the same applies to `>`, `|`, `&&`, and globbing. Spawn a shell whenever shell syntax is needed: `pty_spawn(command: "bash", args: ["-c", "make test </dev/null"])`. `pty_write` is a different shape again: it runs its input through escape-sequence parsing and command extraction before executing, so `data` is keystrokes rather than a command string — anything reading `data` (a guard rule, a log) sees pre-parse input, and a command split across two writes is indistinguishable from two keystroke batches.
