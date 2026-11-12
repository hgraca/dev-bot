---
date: 2026-11-11
keywords: ["devbot", "memory-smoke", "worktree", "init.sh"]
aliases: ["memory smoke tests 4 and 5 fail", "latent/global symlink worktree"]
---

# Memory smoke tests 4–5 fail from a linked worktree

`src/agentic/memory/tests/memory-smoke_tests.bats` asserts that `latent/global` symlinks to the _current checkout's_ `storage/global-memories`, but `init.sh` resolves the central store against the main checkout. Running the suite inside `.agents/worktrees/<slug>` therefore fails tests 4 and 5 (`latent/global symlink points at the dev-bot central store`, `re-run preserves the global symlink`) with an expected/actual pair that differs only by the worktree prefix. Both pass in the main checkout.

Consequence: a docs-only change made in a worktree reports two red tests that are not its fault, and a full `make test-bats` run can look broken. For skill edits, run the skill-integrity subset instead — `BATS_LIB_PATH="$(npm root -g)" bats --filter "skill files" src/agentic/memory/tests/memory-smoke_tests.bats` (the manual `BATS_LIB_PATH` is required; without it every test fails in `setup()` with `Could not find library 'bats-support'`). Treat 4–5 in a worktree as a known environment defect, not a regression; the real fix is making `init.sh` resolve the storage root from the worktree's own `git rev-parse --show-toplevel`.
