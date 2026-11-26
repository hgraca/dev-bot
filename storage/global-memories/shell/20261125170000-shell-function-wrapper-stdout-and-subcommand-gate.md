---
date: 2026-11-25
keywords: ["shell", "bashrc", "stdout", "wrapper", "cli"]
aliases: ["bashrc function shadowing a binary", "wrapper pollutes stdout", "command mycli recursion"]
trigger-on: ["bashrc-cli-wrapper", "shell-function-shadowing-binary"]
---

## A shell-function wrapper must keep the wrapped CLI's stdout clean and gate the pre-step on the subcommands that need it

Wrapping a CLI in a `~/.bashrc` function (`mycli() { prep; command mycli "$@"; }`) breaks it in two ways that pass every happy-path test. First, whatever `prep` prints lands on fd 1 ahead of the command's own output, so anything that parses or evals stdout — `eval "$(mycli completion bash)"`, `mycli status --json`, `mycli api snapshot` — gets the banner plus the payload and fails silently; a completion eval in a shell rc also re-runs `prep` on every new shell. Redirect the helper to fd 2 (`prep 1>&2`) so it stays visible without touching the payload. Second, running the pre-step on every invocation charges it to fast read-only subcommands and lets concurrent callers race the same side effects; gate it with `case "${1:-}" in ""|--session*|session) prep;; esac` on the forms that actually need it, and bypass the function inside itself with `command mycli` (a bare `mycli` re-enters the function). Prefer `if command -v dep >/dev/null 2>&1; then prep 1>&2 || echo "mycli: prep failed — starting anyway" >&2; fi` over `cmd && prep`: a failure last in an `&&` list aborts a caller running under `set -e`, and either way the failure is otherwise silent. Helper functions defined by an installer (`warn`, `_ok`) do not exist in the user's shell — the wrapper may only use shell builtins.
