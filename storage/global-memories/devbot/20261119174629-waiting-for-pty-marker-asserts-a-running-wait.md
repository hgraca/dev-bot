---
date: 2026-11-19
keywords: ["devbot", "waiting-for-pty", "status-markers", "subagent-resume", "shell-strategy"]
aliases: ["WAITING_FOR_PTY without a process", "announced wait never started", "marker self-assertion"]
trigger-on: ["agent-status-markers", "waiting-for-pty"]
---

## `[WAITING_FOR_PTY]` asserts a running wait — start it before you announce it

The marker is a self-assertion about a process the agent claims to be waiting on; nothing in the harness checks it, so an agent can announce a wait it never started and the work silently stalls (observed twice in one session, by the agent that had just written the rule). Two rules close it: start the long-running call **first**, and emit the marker as the last thing in the message. A start call that failed or never happened is `[BLOCKED]` with the failure surfaced, not a wait.

Three cases are not that failure:

- **A wait that already finished** — read its result and continue; `[PARTIAL]` if work remains. `[BLOCKED]` would misreport a finished job as an external blocker.
- **A session that cannot wait** — a subagent on opencode v1 (the plugin throws `[pty-subagent]` for every `pty_*` call in a child session) or any harness without a PTY: run the job as a blocking call with an explicit `timeout` and report its result.
- **An orchestrator receiving the marker from a subagent** — no exit notification reaches the parent's `task` call, so it is an invalid delegation: re-delegate asking for the blocking form; do not wait.

Enforcement now exists, in the weakest honest form: the `session.idle` hook re-validates the last assistant message with `--require-wait`, and the validator rejects `[WAITING_FOR_PTY]` when the message carries no completed `pty_spawn` and no `bash`/`shell` with `background: true`. It proves the wait was _started_ in that message, not that the process is still alive — a process that died silently still passes. Only the hook can judge it: a text-only caller has no tool parts, so the flag is opt-in and a manual invocation keeps marker-only semantics.
