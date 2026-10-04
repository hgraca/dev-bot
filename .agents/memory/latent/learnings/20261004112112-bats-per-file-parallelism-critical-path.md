---
date: 2026-10-04
keywords: ["devbot", "bats", "test-suite", "parallelism", "refactor"]
aliases: ["no-parallelize-within-files", "largest test file bottleneck"]
---

# BATS parallelizes per file — one oversized file is the whole critical path

`make test` runs `bats --jobs 8 --no-parallelize-within-files -r bin/ src/`, so the
parallelism unit is the **file**: tests inside a file run serially. When one file holds
a large share of the slow tests it becomes the critical path, and the wall time tracks
that file's serial total — not the job count.

Measured 2026-10-04: `src/agentic/refactor/tests/refactor_tests.bats` held 208 tests
(~125 ≥1s, four of the five slowest at 16-22s) in one file; `make test` ran ~9 min.
Splitting it by section into 9 files + a `load`ed `refactor_test_helper.bash` (shared
`setup()`/helpers) dropped the module to 1m55s and the whole suite to ~4m39s — the same
2037 tests, unchanged.

Caveat vs `20260920164034-01-test-suite-is-io-contention-bound`: splitting helps when a
single file is disproportionately large/slow (as the refactor module now is); when work
is spread evenly the suite is contention-bound and redistributing buys little. Split by
section — never mid-test — and extract shared helpers into a `load`ed `.bash` file so
each file stays self-contained.
