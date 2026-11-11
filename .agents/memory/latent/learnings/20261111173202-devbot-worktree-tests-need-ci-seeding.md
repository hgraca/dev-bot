---
date: 2026-11-11
keywords: ["devbot", "worktree", "make test", "bats", "seeding"]
aliases: ["linked worktree tests", "DEV_BOT_ROOT in worktree", "tools farm"]
see: ["learnings/20261111170200-memory-smoke-tests-fail-in-linked-worktree.md"]
---

# A linked worktree needs CI-style seeding before `make test` means anything

`git worktree` inherits tracked files only. A dev-bot worktree therefore lacks every gitignored fixture the suite depends on, and a first `make test` there reports dozens of unrelated failures:

- `.devbot.global.jsonc` — `bin/tests/commands_tests.bats` copies it in `setup()` (`cannot stat`), and the module-map fixtures read it;
- `.env`;
- `.devbot.project.jsonc` and the `.agents/{skills,agents,commands,tools}` farms — `devbot list tools` prints an empty table without them.

Reproduce CI's fixtures (`.github/workflows/ci.yml` “Prepare test fixtures”) before trusting a run: copy `.devbot.global.jsonc` and `.env` into the worktree, then `bash src/tools/devbot-cli/init.sh "$PWD"` there — the CLI resolves its own root from its path, so the farms point into the worktree, not the main checkout.

## Environment, not just files

The harness exports `DEV_BOT_ROOT` (the **main** checkout) plus `DEV_BOT_SESSION_ID` / `DEV_BOT_AGENT_NAME` into every bash call. Running the suite with that inherited `DEV_BOT_ROOT` makes `memory/init.sh` link `latent/global` to the main checkout's store (memory smoke tests 4–5 fail) and points every `${DEV_BOT_ROOT}` read at the wrong tree. Run the suite as `env -u DEV_BOT_SESSION_ID -u DEV_BOT_AGENT_NAME DEV_BOT_ROOT="$PWD" make test` — unsetting `DEV_BOT_ROOT` entirely is worse: `bin/tests/delegate_tests.bats` sources a sandbox `init.sh` that requires the variable under `set -u`.

The nine `src/agentic/memory/tests/search-memories_e2e_tests.bats` cases can still fail locally with `ERR_DLOPEN_FAILED` (`NODE_MODULE_VERSION` mismatch) when the globally installed `qmd`'s `better-sqlite3` was built for another Node major — they pass in CI, which pins Node 22. Verify against the main checkout before blaming the change.
