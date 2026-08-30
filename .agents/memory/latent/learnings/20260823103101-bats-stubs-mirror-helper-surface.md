---
date: 2026-08-23
keywords: ["devbot", "bats", "test-stub", "functions.sh"]
---

# BATS test stubs mirror the functions.sh helper surface

`bin/tests/init_tests.bats` and `bin/tests/up_compose_opts_tests.bats` isolate tests by writing a minimal fake `functions.sh` that defines only the helpers the tested code calls (`_warn`, `_error`, `_info`, etc.). Adding a new helper to `src/_shared/functions.sh` without updating these stubs makes the exercised script fail with `<helper>: command not found`. This bit after `_fatal` was introduced — `up_compose_opts_tests` test 9 ("missing .devbot.global.jsonc") failed because its stub lacked `_fatal`. Whenever adding an output helper to `functions.sh`, mirror it in both `.bats` stubs.
