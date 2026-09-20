---
date: 2026-09-20
keywords: ["shell", "bats", "setup_file", "BATS_FILE_TMPDIR", "parallel"]
trigger-on: ["bats-shared-fixture", "bats-parallel-jobs"]
---

## bats runs each test in its own process and its tmpdir is per file — so shared fixtures need `export` and an atomic publish

A variable assigned in `setup_file()` reaches the tests only if it is `export`ed, because bats executes every test in a separate process; without the `export` the value is silently empty and any optimisation keyed off it quietly never runs — the failure mode is a silently-unused fast path, not an error, so it survives a green suite. `BATS_FILE_TMPDIR` is per **file**, not per test, and stays so even when bats parallelises within files, which makes a lazily-built shared fixture there (`[[ -d $cache ]] || build`) a check-then-build race: the loser hands a half-seeded directory to whatever consumes it. Publish such a fixture atomically — seed into `"$cache.$$"` and `mv` it into place, letting the first writer win and the rest discard their staging copy.
