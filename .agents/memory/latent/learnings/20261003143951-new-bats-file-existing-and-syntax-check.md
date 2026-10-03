---
date: 2026-10-03
keywords: ["bats", "test", "shell", "convention"]
---

# Adding a BATS file: check for an existing same-subject test, and use BATS — not `bash -n` — as the syntax check

Two traps when adding a BATS test. First, check `bin/tests/` and `src/**/tests/` for an existing file on the same subject before creating one, matching both `-` and `_` spellings: a new `seed-claude-config_tests.bats` was added beside the existing `seed_claude_config_tests.bats`, and the older file kept asserting the pre-change behaviour — it failed only in the full suite, because the quick scoped run exercised the new file. Second, `bash -n <file>.bats` is not a valid check: it also rejects known-good BATS files (the `@test "name" { … }` form), so a failure there says nothing. Run the file with `BATS_LIB_PATH="$(npm root -g)" bats <file>` instead — a genuine parse error surfaces immediately as `bats-gather-tests … unexpected EOF while looking for matching quote`, which nested quotes inside `run bash -c "source '…'; fn 'arg'"` can trigger; sourcing the library in `setup()` and calling helpers directly (`run helper arg`) avoids that nested-quoting form entirely.
