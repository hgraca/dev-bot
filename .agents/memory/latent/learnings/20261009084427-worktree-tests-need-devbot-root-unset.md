---
date: 2026-10-09
keywords: ["devbot", "worktree", "DEV_BOT_ROOT", "test-harness"]
---

# Tests run from a linked worktree silently exercise the main checkout

## The trap

The agent shell exports `DEV_BOT_ROOT` pointing at the **main** checkout. A linked git worktree
(`<main>/.agents/worktrees/<slug>`) is a nested checkout with its own `src/`, but when a BATS or
Python test sources `src/_shared/functions.sh` the library keeps the inherited value
(`export DEV_BOT_ROOT="${DEV_BOT_ROOT:-...}"`) — so it resolves helper and config paths from the
MAIN checkout, not the worktree under test. A test can therefore pass or fail against main's code:
a helper that only exists in the worktree is "not found", and every `_devbot_get_config` read
falls back to main's config. This bit the supervisor-memory BATS suite: the resolver helper
appeared absent until the tests pinned `env -u DEV_BOT_ROOT`.

## The rule

Run tests from a linked worktree with `env -u DEV_BOT_ROOT` (or explicitly set it to the worktree
root) so the library derives its root from the sourced file's location. Also note a raw
`git worktree add` skips the devbot tool's dependency linking: symlink `node_modules`/`vendor` and
copy `.devbot.{global,project}.jsonc` into the worktree first, or the suites cannot build/run.
