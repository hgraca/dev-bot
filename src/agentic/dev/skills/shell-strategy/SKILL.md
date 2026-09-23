---
name: devbot:shell-strategy
description: "Use when running any shell command — picking between the bash tool and a PTY session."
---

# Shell Strategy

Every shell command runs on one of two channels: the built-in `bash` tool, or a PTY session (`pty_spawn` / `pty_write` / `pty_read` / `pty_kill`). Pick the channel before running, not after it times out.

## When to Apply

- Any time you run a shell command — including from inside a skill or workflow.

## Choosing the channel

| Situation                                                                       | Channel     |
| ------------------------------------------------------------------------------- | ----------- |
| Quick, deterministic, non-interactive (`git status`, `ls`, `rg`, `git add`)     | `bash` tool |
| May outlive the bash tool's timeout — test suites, builds, migrations, installs | PTY         |
| Prompts for input — REPL, interactive auth, a script that calls `read`          | PTY         |
| Output must be watched while it runs — dev server, watch mode                   | PTY         |

The distinction is **time, not command length**. A one-liner that runs for ten minutes is a PTY command; a long command line that returns instantly is a bash command.

## Running in a PTY

- `pty_spawn` starts the session; pass `notifyOnExit` instead of polling for completion.
- Read output with `pty_read` (`offset` / `limit` / `pattern`) — no need to wait for the process to finish.
- `pty_kill` the session when done, or it lingers in the PTY monitor.

### MUST NOT

- **Never redirect a PTY command's output** (`>`, `2>&1`, `| tee`). The PTY _is_ the output channel; redirection hides the run from the user's PTY web UI, which shows exactly what the terminal receives and nothing that was redirected away.
- **Never background a PTY command with `&`** — the PTY is already the session.

### MUST

- **`pty_spawn` execs the command directly, without a shell — wrap yourself in one when you need shell syntax.** `pty_spawn(command: "make", args: ["test", "</dev/null"])` hands `make` the literal argument `</dev/null`; the redirect never happens. Spawn a shell instead: `pty_spawn(command: "bash", args: ["-c", "make test </dev/null"])`.
- **Wire stdin from `/dev/null` for commands that expect a non-interactive shell.** A PTY makes stdin a tty, so a command that branches on `[ -t 0 ]` or prompts blocks forever waiting for input that never comes. Redirecting _stdin_ is right; redirecting _stdout_ is what hides the run.

## Waiting for a duration

When something must be verified after a fixed delay — a deploy settling, a CI run finishing, a cache entry expiring — spawn a PTY running `sleep` and let its exit wake you:

```text
pty_spawn(command: "sleep", args: ["300"], notifyOnExit: true, title: "wait 5m")
```

Then end your turn. The `<pty_exited>` notification wakes you; run the verification then. Do not `pty_read`-poll the sleeping session, block a `bash` call with `sleep`, or loop on `timeout` — the notification is the signal. `sleep` is a binary, so the no-shell spawn rule above is satisfied without a wrapper. Kill the session with `pty_kill(id, cleanup: true)` once it has woken you.

## Gotchas

- **Commit through bash, never a PTY.** The post-commit hooks (memory capture, graph indexing) are wired to the bash tool's after-hook — a commit run in a PTY silently skips them. `git commit` is quick, so bash is the right channel anyway.
- **PTY sessions do not inherit `DEV_BOT_SESSION_ID`.** The session environment is injected into the bash tool only; a tool that reports the session id (e.g. the grade-tools skill) must run through bash.
- **A PTY session outlives the tool call.** Nothing stops it when the turn ends — kill it explicitly.

## Other harnesses

claudecode has no PTY. Use its background-execution equivalent for long-running commands, and the ordinary shell tool for quick ones.
