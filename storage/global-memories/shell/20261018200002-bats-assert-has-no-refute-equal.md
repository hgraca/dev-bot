---
date: 2026-10-18
keywords: ["shell", "bats", "bats-assert", "refute_equal", "assert_not_equal"]
aliases: ["bats helper missing", "command not found in bats test"]
---

## bats-assert has no `refute_equal` — use `assert_not_equal`

A test calling `refute_equal` fails with `refute_equal: command not found` (status 127), not an assertion error, even when `setup()` loads `bats-support` and `bats-assert`. The installed bats-assert exposes `assert_equal`, `assert_not_equal`, and a `refute_*` family for output, lines and regex — but there is no `refute_equal`. The 127 reads like a broken test environment rather than a missing helper, so it can waste a debugging pass. Use `assert_not_equal <actual> <expected>`.
