---
date: 2026-09-20
keywords: ["make-test", "test-runtime", "verification"]
---

# `make test` can exceed a 15-minute timeout — verify in phases

The full suite no longer finishes inside a 15-minute shell timeout on this machine: a single `update_tests.bats` case takes ~33s and several others run 4–7s. A run then ends with `make: *** [Makefile:127: test] Terminated` and reads as a failure when the suite was merely unfinished — one run reported 1217 of 1235 BATS cases `ok` with zero failures at the cut-off.

Verify in the three phases the Makefile runs and check each separately:

```bash
BATS_LIB_PATH="$(npm root -g)" bats -T -r src/ bin/ </dev/null
bun test src/
for f in $(find src -name 'test_*.py' | sort); do (cd "$(dirname "$f")" && python3 -m unittest "$(basename "$f" .py)") || failed=1; done
```

Two parsing gotchas when scripting the checks: `python3 -m unittest <file> | tail -1` can print a blank line for suites whose stdout continues past the summary (`test_search_memories` does), so match `^OK$` / `^FAILED` instead of the last line; and `bats <file>` run alone needs `BATS_LIB_PATH` or every test fails in `setup()`.
