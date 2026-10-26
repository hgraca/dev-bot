---
date: 2026-10-26
keywords: ["dev-bot", "bats", "worktree", "global-config", "test-suite"]
---

## A dev-bot worktree has no `.devbot.global.jsonc`, and the BATS suite assumes one

Running `make test-bats` from a linked worktree (`.agents/worktrees/<slug>`) fails about fourteen tests in `bin/tests/commands_tests.bats` and the `devbot init`/`help` cases with:

```
#   `cp "${PROJECT_ROOT}/.devbot.global.jsonc" "${GLOBAL_CONFIG}"' failed
```

`worktree.sh create` copies only tracked files, and `.devbot.global.jsonc` is gitignored (it is machine-owned and reconciled from `.devbot.global.dist.jsonc`), so a fresh worktree has none. Link the main checkout's copy into the worktree root — gitignored, so it never shows in `git status`:

```bash
ln -s <main-checkout>/.devbot.global.jsonc <worktree>/.devbot.global.jsonc
DEV_BOT_ROOT="$PWD" make test-bats     # the DEV_BOT_ROOT override has its own trap, see 20261024001641
```

Two families stay red in a worktree no matter what, and are not worth chasing: the compose project-name tests (`PROJECT_NAME` derives from the checkout directory name, which is the worktree slug) and `devbot list tools` (a worktree has no `.agents/` runtime farm, so the tool links are absent). Both pass in the main checkout — verify a suspected failure there before treating it as a regression.
