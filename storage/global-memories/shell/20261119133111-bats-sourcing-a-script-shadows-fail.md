---
date: 2026-11-19
keywords: ["shell", "bats", "bats-assert", "testing"]
aliases: ["fail shadowing", "vacuous assertions", "green tests that prove nothing"]
trigger-on: ["bats-sourcing-script-under-test"]
---

## Sourcing a script that defines `fail()` makes every bats-assert assertion vacuous

`bats-assert` implements `assert_output`, `assert_success` and friends as a final `| fail` — they
report a failure by calling the `fail` function from `bats-support`. A test file that `source`s the
script under test in `setup()` and that script defines its own `fail() { printf 'FAIL …'; }` replaces
the harness function, so every assertion in the file succeeds unconditionally: 43/43 green while
proving nothing. The fix is to namespace the script's result helpers (`probe_pass`, `probe_fail`,
`probe_unknown`) so sourcing cannot shadow anything, and to add a guard test that is itself a bare
assertion — `! grep -qE '^[[:space:]]*(function[[:space:]]+)?(pass|fail|unknown|info)[[:space:]]*\(\)'
script.sh` — never `run grep` + `assert_failure`, because that guard would be disarmed by the very
shadowing it exists to detect. Prove the guard by appending `fail() { :; }` to the script and
confirming the suite reddens. Symptom to recognise: a test file goes green the moment its subject is
sourced, and stays green when you deliberately break the behaviour.
