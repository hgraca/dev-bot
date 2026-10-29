---
date: 2026-10-29
keywords: ["devbot", "bats", "bats-support", "npm-root"]
trigger-on: ["devbot-bats-single-file"]
---

## A targeted BATS run needs `BATS_LIB_PATH="$(npm root -g)"`

`bats src/agentic/<module>/tests/<name>_tests.bats` fails in `setup()` with `Could not find library 'bats-support' relative to test file or in BATS_LIB_PATH`, because the Makefile exports that variable and a bare invocation does not. Prefix a targeted run with it: `BATS_LIB_PATH="$(npm root -g)" bats <files>`. Only suites that call `bats_load_library bats-support`/`bats-assert` fail this way (e.g. `src/agentic/dev/tests/software-development_tests.bats`); suites that only `grep` still pass, so a mixed selection looks half-broken and the failure is easy to mistake for a real assertion error — the tell is the message coming from `setup()` rather than from a test body. `make test` / `make test-bats-slice` set the variable themselves and stay the preferred entry points; the prefix is only for iterating on one file.
