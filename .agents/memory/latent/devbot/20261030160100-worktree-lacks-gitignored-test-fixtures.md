---
date: 2026-10-30
keywords: ["devbot", "worktree", "tests", "env", "global-config"]
trigger-on: ["worktree-test-fixtures"]
---

# Repo-Wide Tests Fail in a Worktree Without Its Gitignored Fixtures

`worktree.sh create` links `vendor/` and `node_modules/` but does not copy gitignored config. Several `bin/tests` suites `cp` `${PROJECT_ROOT}/.devbot.global.jsonc`, and the compose tests need `.env`; in a fresh worktree both are absent, so tests fail with `cp: cannot stat` or an empty `docker compose config` (which then looks like a project-name bug). For verification, copy them locally — `cp .devbot.global.dist.jsonc .devbot.global.jsonc` mirrors what CI seeds, and copy `.env` from the main checkout — then re-run. Both stay ignored and must never be committed.
