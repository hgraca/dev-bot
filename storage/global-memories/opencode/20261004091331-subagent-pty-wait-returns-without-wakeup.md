---
date: 2026-10-04
keywords: ["opencode", "pty", "subagent", "task"]
aliases: ["WAITING_FOR_PTY parent", "subagent PTY continuation lost"]
---

## A subagent's notifyOnExit PTY finishes, but the `task` result is already frozen

The `task` tool runs a subagent in a child session and returns as soon as the subagent's **turn ends**; `[WAITING_FOR_PTY]` is a dev-bot convention meaning "turn ended, work pending", which opencode does not know, so it treats the pause as completion and hands the parent the bare marker. The exit notification is **not** lost — opencode-pty posts `<pty_exited>` to the spawning session (`session.parentSessionId`), so the child session **does resume** and the subagent finishes its work; but the parent's `task` call already resolved, and the child's post-pause messages are never surfaced to the parent. Verified in the opencode DB: a reviewer child resumed at 06:50:24 and emitted its verdict at 06:51:20, while the parent held no copy until a manual `task_id` resume 13 minutes later. Consequence: `notifyOnExit` + `[WAITING_FOR_PTY]` is reliable only in the top-level session — a subagent must not end its turn on a PTY (run long jobs with blocking `bash` and an explicit `timeout`). The proper fix belongs upstream: opencode-pty could walk `session.parent_id` and notify the root session, or opencode's `task` tool could await a child's true terminal state rather than its first turn-end. Until then, dev-bot enforces the safe subset in `on-hooks.ts` (`tool.execute.before`): every `pty_*` call from a child session is rejected with `[pty-subagent]`, so subagents fall back to `bash` + an explicit timeout (commit `aa882482`; verified live — a subagent's `pty_spawn` is blocked, the primary's is allowed).
