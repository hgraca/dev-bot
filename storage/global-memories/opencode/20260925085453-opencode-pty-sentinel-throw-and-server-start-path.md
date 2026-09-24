---
date: 2026-09-25
keywords: ["opencode", "opencode-pty", "command-sentinel", "pty-server"]
trigger-on: ["opencode-pty-command", "opencode-pty-server"]
---

## opencode-pty signals "handled" by throwing, and starts its server only from a command

`opencode-pty`'s `command.execute.before` handler intercepts `pty-show-server-url` and `pty-open-background-spy`, lazily creates the PTY HTTP server on first use, posts the server URL into the session, and then **throws `Error("Command handled by PTY plugin")`**. That throw is a deliberate sentinel telling opencode not to run the command's template, so it arrives _after_ the work has already succeeded — reading it as a failure misreports a working server as unavailable. Two related facts matter when reasoning about the PTY server's state: it is created **only** inside that command handler, so `pty_spawn`/`pty_write` and the session manager never start it (a sidebar that lists PTY sessions therefore cannot rely on a spawn having brought the server up); and the server is a plugin-level, per-opencode-process object bound to a random port, so its origin must be re-resolved after every restart.
