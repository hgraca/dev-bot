---
date: 2026-10-19
keywords: ["devbot", "worktree", "make-test", "devbot-root", "search-memories"]
aliases: ["full suite in a linked worktree", "DEV_BOT_ROOT worktree", "worktree test failures"]
---

# Running dev-bot's full suite in a linked worktree needs the runtime files copied

A fresh linked worktree is tracked files only, while `make test` expects the machine's gitignored runtime files and a `DEV_BOT_ROOT` that points at the checkout under test.

## Setup

Copy these into the worktree before running the suite (they are all gitignored — never stage them):

- `.devbot.global.jsonc` (and its `.jsonc~` backup) — otherwise the `bin/tests/commands_tests.bats` and `src/tools/devbot-cli/tests/devbot_tests.bats` fixtures fail on `cp: cannot stat`.
- `.env` — the compose-fragment tests run `docker compose config`, which fails without it (the include resolves an `env_file`).
- `.agents/tools` (the farm) — `devbot list tools` reads it, so two `commands_tests.bats` cases come back empty without it.
- `storage/refactor/rector/vendor` and `src/agentic/refactor/tests/fixtures/php/with-rector/vendor` — the PHP-engine and end-to-end refactor tests report `no Rector engine found` / `Could not open input file: /refactor-engine/vendor/bin/rector`. Copy them (`cp -a`): a symlinked Rector vendor breaks the Docker mount, and hard links can fail across filesystems.

Run with `DEV_BOT_ROOT="<worktree>" make test`. Unsetting it makes `opencode/tests/delegate_tests.bats` fail with `DEV_BOT_ROOT: unbound variable`; leaving it at the main checkout makes the memory smoke test assert the main checkout's `storage/global-memories` target.

## Known remaining failure

With the setup above the only failure is `src/agentic/memory/tests/search-memories_e2e_tests.bats` → "missing --collection falls back to auto-detection". It passes in the main checkout; a linked worktree shares the central memory/qmd store, so the isolated fixture collides with the main index. Treat it as environmental for a worktree run, not as a regression.
