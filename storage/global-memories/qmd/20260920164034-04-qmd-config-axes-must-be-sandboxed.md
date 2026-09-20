---
date: 2026-09-20
keywords: ["qmd", "QMD_CONFIG_DIR", "XDG_CACHE_HOME", "test-isolation"]
---

## qmd writes to two config axes — sandbox both or a test edits the developer's real index

`qmd` reads its collection registry from `QMD_CONFIG_DIR` (the `index.yml` holding every collection) and its index cache from `XDG_CACHE_HOME`. Any test or script that reaches the real `qmd` CLI without overriding both registers into the developer's own `~/.config/qmd/index.yml` — `memory/tests/memory-smoke_tests.bats` ran `init.sh`, whose `qmd collection add dev-bot-global` polluted the real registry while the test's own assertion then read that pollution back, so a green test proved nothing about isolation. Verify isolation by inspecting the sandbox config (run bats with `--no-tempdir-cleanup` and read the file under the test's tmpdir) rather than by the assertion passing, since the real config already contains the collection; the `search-memories_e2e` suite is the reference pattern, with a per-test `mktemp -d` for each axis.
