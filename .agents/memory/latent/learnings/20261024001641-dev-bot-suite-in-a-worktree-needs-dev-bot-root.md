---
date: 2026-10-24
keywords: ["dev-bot", "bats", "worktree", "DEV_BOT_ROOT", "test-suite"]
---

# Running dev-bot's BATS suite from a linked worktree needs DEV_BOT_ROOT

## What happens

`make test` / `make test-bats` run inside `.agents/worktrees/<slug>` inherits whatever `DEV_BOT_ROOT` the session already exported. In a polyrepo session that value is the **main checkout** (`/…/Get-e/dev-bot`), not the worktree, and two suites fail in opposite directions:

- **DEV_BOT_ROOT points at the main checkout** — `src/agentic/memory/tests/memory-smoke_tests.bats` fails: `latent/global` is linked to the main checkout's `storage/global-memories` while the test expects the worktree's path.
- **DEV_BOT_ROOT unset** — `src/harnesses/opencode/tests/delegate_tests.bats` fails: the generated sandbox `init.sh` expands `${DEV_BOT_ROOT:?}` under `set -u`.

## The command that works

```shell
DEV_BOT_ROOT="$PWD" make test        # from the worktree root
```

That is exactly what CI does (`DEV_BOT_ROOT: ${{ github.workspace }}` in `.github/workflows/ci.yml`), so a green local run then means the same thing as a green CI run.

## Why it is easy to miss

Neither failure message mentions the worktree or the variable, so both read like a real regression in unrelated suites — and "export it" / "unset it" are each the wrong fix for the other case.
