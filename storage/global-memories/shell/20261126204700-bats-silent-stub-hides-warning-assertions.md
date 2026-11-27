---
date: 2026-11-26
keywords: ["bats", "shell", "test-stub", "assert_output", "warning"]
aliases: ["silent stub swallows output", "_warn stub true"]
---

## A silent stub makes every assertion about that output vacuous

A BATS sandbox that stubs `_warn() { true; }` to keep test output quiet also removes the ability to test any warning: `assert_output --partial "…"` fails with an empty output and no clue, and a test that _should_ fail on a missing warning passes. The same holds for `_info`, `_ok` and `_skip` when a test needs to assert their text.

Override the stub inside the `bash -c` that drives the function under test — after sourcing, so it wins — instead of editing the shared stub:

```bash
run bash -c '
  source "'"${SANDBOX}"'/bin/x.sh"
  _warn() { echo "WARN: $*"; }
  _thing_under_test
'
assert_output --partial "WARN: up lock not held"
```

Editing the shared stub to echo is the alternative, but it changes output for every test in the file and can break the silence assertions of unrelated cases; a per-test override keeps the blast radius to the test that needs it. Either way, confirm the assertion can fail — delete the `_warn` call from production and watch it go red.
