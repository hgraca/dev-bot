---
name: devbot:shell-strategy
description: "Use when running any shell command — choosing the channel and keeping its output visible."
---

# Shell Strategy

Pick the channel before running a command, not after it times out. Which channels exist depends on the harness:

| Harness     | Channels                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------- |
| opencode v1 | built-in `bash` tool, or a PTY session (`pty_spawn` / `pty_write` / `pty_read` / `pty_kill`) |
| opencode v2 | one `shell` tool — no PTY; carries `timeout` and `background` options                        |
| claudecode  | its shell tool, with background execution for long runs                                      |

## When to Apply

- Any time you run a shell command — including from inside a skill or workflow.

In a polyrepo project, resolve the owning project of the command
(`devbot tool project-for-path <path>`) and run it from that project's directory,
against that project's container. The polyrepo root's containers are not the
project's.

## Keep the output visible

The user watches the tool's output; you read the tool result. Both are lost when the command's output is redirected or piped away.

- **Never end a long command with `| tail`, `| head`, `> file`, or `2>&1 | tail`.** A pipe to `tail` buffers everything until the process exits, so nothing streams; if the command then times out or moves to the background, the result is empty and the v2 TUI shows _No captured output. Output redirected to files is not shown here._ Filter with a dedicated search tool afterwards, never with a pipe that hides the run.
- **Let the tool truncate.** The v2 `shell` tool returns a preview and saves the full result to a file automatically — manual filtering is unnecessary.
- **Pass an explicit `timeout` for known-long work (milliseconds).** The v2 `shell` tool's foreground timeout defaults to **120000 ms (2 minutes)**; when it expires the command moves to the background and the result carries only an output-file path. A test suite or build deserves a generous value (e.g. `timeout: 900000`) or `timeout: 0` to disable it.
- **Use `background: true` when the work should outlive the turn** — dev server, watch mode, a very long suite. It returns immediately and notifies you on completion; end your turn and read the output then. Do not poll.
- **Use the tool's `workdir` instead of `cd <path> &&`.** It keeps the command line readable and the working directory explicit.

```text
# Bad — buffers the whole run, then exceeds the 120s foreground timeout:
cd /repo && make test 2>&1 | tail -60

# Good — streams, is truncated for you, and gets a realistic timeout:
shell(command: "make test", workdir: "/repo", timeout: 600000)
```

## Choosing the channel

| Situation                                                                   | opencode v1 | opencode v2 / claudecode                      |
| --------------------------------------------------------------------------- | ----------- | --------------------------------------------- |
| Quick, deterministic, non-interactive (`git status`, `ls`, `rg`, `git add`) | `bash` tool | `shell` tool                                  |
| May outlive the tool's timeout — test suites, builds, migrations, installs  | PTY         | `shell` with an explicit `timeout`            |
| Prompts for input — REPL, interactive auth, a script that calls `read`      | PTY         | not supported; use a terminal the user drives |
| Output must be watched while it runs — dev server, watch mode               | PTY         | `shell` with `background: true`               |

The distinction is **time, not command length**. A one-liner that runs for ten minutes is a long-running command; a long command line that returns instantly is not.

## Running in a PTY (opencode v1)

- `pty_spawn` starts the session; pass `notifyOnExit` instead of polling for completion.
- Read output with `pty_read` (`offset` / `limit` / `pattern`) — no need to wait for the process to finish.
- `pty_kill` the session when done, or it lingers in the PTY monitor.

### PTY is top-level only

The `pty_*` tools are available to the **primary agent only**; a `task` subagent runs in a child session and the harness blocks them there. A subagent must run a long command with the `bash` tool and an explicit `timeout` (milliseconds) — the parent is already waiting on the task, so blocking there is correct. Reason: `task` returns the moment a subagent's turn ends, so a subagent that pauses on a `notifyOnExit` PTY never surfaces its continuation to the parent (the child does resume on `<pty_exited>`, but its later turns are not delivered to the `task` caller).

### MUST NOT

- **Never redirect a PTY command's output** (`>`, `2>&1`, `| tee`). The PTY _is_ the output channel; redirection hides the run from the user's PTY web UI, which shows exactly what the terminal receives and nothing that was redirected away.
- **Never background it with `&`** — the PTY is already the session.

### MUST

- **`pty_spawn` execs the command directly, without a shell — wrap yourself in one when you need shell syntax.** `pty_spawn(command: "make", args: ["test", "</dev/null"])` hands `make` the literal argument `</dev/null`; the redirect never happens. Spawn a shell instead: `pty_spawn(command: "bash", args: ["-c", "make test </dev/null"])`.
- **Wire stdin from `/dev/null` for commands that expect a non-interactive shell.** A PTY makes stdin a tty, so a command that branches on `[ -t 0 ]` or prompts blocks forever waiting for input that never comes. Redirecting _stdin_ is right; redirecting _stdout_ is what hides the run.
- **Do not redirect stdin when the command needs a TTY.** `docker compose exec`/`run` with `-it` and a `make up` that attaches to a TTY-enabled container fail with "stdin is not a terminal" when stdin is `/dev/null`. Omit the redirect for those, or pass `-T` to compose. The no-input rule applies to commands that branch on interactivity, not to commands that require a terminal.

## Waiting for a duration

When something must be verified after a fixed delay — a deploy settling, a CI run finishing, a cache entry expiring — do not block a tool call with `sleep` and do not poll in a loop.

- **opencode v1:** spawn a PTY running `sleep` with `notifyOnExit: true`, then end your turn. The `<pty_exited>` notification wakes you; run the verification then. Kill the session with `pty_kill(id, cleanup: true)` once it has woken you. `sleep` is a binary, so the no-shell spawn rule above is satisfied without a wrapper.
- **opencode v2:** run the work itself with `background: true` (or a long `timeout`) and end your turn; the completion notification wakes you.
- **claudecode:** use its background execution and end your turn.

End the turn with `[WAITING_FOR_PTY]` only when one of those asynchronous waits actually started; a blocking call continues in the same turn. Its precondition and the no-PTY cases are in `devbot:agent-communication`.

## Gotchas

- **A TTY-enabled container is the `/dev/null` exception.** `make up` and `docker compose exec -it` need a terminal; redirecting stdin there turns a working command into an error.
- **Commit through bash, never a PTY.** The post-commit hooks (memory capture, graph indexing) are wired to the bash tool's after-hook — a commit run in a PTY silently skips them. `git commit` is quick, so bash is the right channel anyway.
- **PTY sessions do not inherit `DEV_BOT_SESSION_ID`.** The session environment is injected into the bash tool only; a tool that reports the session id (e.g. the grade-tools skill) must run through bash.
- **A PTY session outlives the tool call.** Nothing stops it when the turn ends — kill it explicitly.
- **`notifyOnExit` only wakes the top-level session.** A subagent that ends its turn on a PTY is not resumed into the parent's `task` call — see "PTY is top-level only" above.
- **A backgrounded shell command hides its output too.** The result carries an output-file path, not the text; read that file only when you actually need the details, and never start a second copy while the first runs.
