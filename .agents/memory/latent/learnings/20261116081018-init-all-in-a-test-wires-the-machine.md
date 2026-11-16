---
date: 2026-11-16
keywords: ["devbot", "bats", "init", "test-hermeticity"]
aliases: ["init --all in a test", "gitignore dirty after make test", "bats bin hangs"]
---

# A bats test that runs `bin/init.sh --all` initialises every registered project

`bin/tests/init_parallel_tests.bats` exercised the `-j 08` parser by running the real `bin/init.sh --all -j 08` with no config override. `--all` reads the machine's `projects` array, so every `make test` (and any standalone `bats bin/tests`) wired **all ~28 registered projects** — minutes of work, one of them this very checkout, which is where the stray `# >>> DEVBOT - module memory` block in `.gitignore` came from — and it left the working tree dirty. Normal `init` also calls `_register_in_global_config`, so such a test can mutate the developer's global config too.

Fix and pattern: give the test an empty project list — `DEV_BOT_GLOBAL_CONFIG="$(mktemp)"` holding `{"projects": {}}` (the resolver honours that variable) — so the parser is exercised without any wiring. The test drops from minutes to ~2 s and writes nothing. Whenever a test must invoke the real `bin/init.sh`, point `DEV_BOT_GLOBAL_CONFIG` at a fixture; treat "the suite left the checkout dirty" as this bug, not as flakiness.
