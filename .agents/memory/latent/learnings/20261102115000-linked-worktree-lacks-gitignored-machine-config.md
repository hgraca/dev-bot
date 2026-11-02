---
date: 2026-11-02
keywords: ["devbot", "worktree", "bats", "devbot-global"]
---

# A linked worktree lacks the gitignored machine config the suite reads

`worktree.sh create` checks out tracked files only, so `.devbot.global.jsonc` and `.env` are absent —
even though `make test-bats` depends on them. `bin/tests/commands_tests.bats` copies
`${PROJECT_ROOT}/.devbot.global.jsonc` in `setup()`, so without the file every `devbot list …` test
fails with `cp: cannot stat …/.devbot.global.jsonc: No such file or directory`, which reads like a
code regression rather than a missing checkout artefact.

Copy both from the main checkout before running the suite:

```bash
cp .devbot.global.jsonc .env .agents/worktrees/<slug>/
```

Both are gitignored, so the copies never enter a commit.

## Second trap: an exported DEV_BOT_ROOT

A session exports `DEV_BOT_ROOT` pointing at the **main checkout**, so tests that resolve
`storage/global-memories` or the `.agents/tools` farm read the main checkout instead of the worktree
(`init.sh: latent/global symlink …`, `devbot list tools …` fail). Point the variable at the worktree
instead — `DEV_BOT_ROOT="$PWD" make test` — see
`20261024001641-dev-bot-suite-in-a-worktree-needs-dev-bot-root.md`.
