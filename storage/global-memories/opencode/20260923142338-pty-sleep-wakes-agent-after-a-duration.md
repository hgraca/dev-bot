---
date: 2026-09-23
keywords: ["opencode", "pty", "notifyOnExit", "sleep", "agent-wait"]
trigger-on: ["pty-wait-duration", "agent-polling-for-completion"]
---

## A PTY running `sleep` with `notifyOnExit` is how an agent waits a duration and gets woken

An agent has no synchronous way to wait: the bash tool carries a fixed timeout, so a `sleep` longer than it is killed before it ever returns, and a poll loop burns turns to answer a single question. `pty_spawn` closes that gap — spawn the `sleep` binary with `notifyOnExit: true` (`command: "sleep", args: ["300"]`), end the turn, and the `<pty_exited>` notification wakes the agent exactly when the delay elapses so it can run the verification it was waiting on. `sleep` is a binary, so the no-shell spawn gotcha needs no `bash -c` wrapper. Do not `pty_read`-poll the sleeping session — the exit notification is the signal — and `pty_kill` it with `cleanup: true` afterwards or it lingers in the monitor. devbot codifies the rule in the `devbot:shell-strategy` skill; agent files carry only the rule plus a pointer to that skill, never the mechanism.
