---
date: 2026-09-20
keywords: ["test-suite", "bats", "contention", "make-test"]
---

# The dev-bot test suite is I/O-contention-bound — cut contended work, don't reshuffle it

`make test` went from 341 s serial to ~88 s (1 713 tests: BATS 1 296, bun 116, python 301, zero skips) via file-level BATS parallelism, `bin/`-then-`src/` ordering, and a job count of CPU count capped at 8 — overridable with `DEV_BOT_TEST_JOBS`, where `1` forces serial and the runner resolves to GNU `parallel`, else `rush`, else a serial fallback with a `WARN:`. The largest early win was not structural at all: one test in the update suite waited 30 s because its mock's orphaned `sleep` kept the captured stdout open — 9% of the whole suite, and shortening the stall to just past the asserted 1 s cap returned ~28 s.

## What the measurements said about the rest

The suite is **contention-bound, not floor-bound**: ~308 s of BATS work at 8 jobs yields only ~3-3.5x, and 16 jobs was _slower_ than 8, so the "longest file sets the floor" model misleads and redistributing work buys little. Splitting the 75 s `bin/tests/update_tests.bats` into three sibling suites (fixtures extracted to a `load`-able `update_helpers.bash`) bought only ~12 s, while caching its fixture origins — deleting ~216 `git init`/commit/tag writes — gave 2.3x on that cluster and visibly lowered its CPU. The lesson: **reduce the contended resource (here, git writes) rather than reshuffle the schedule.**

## Levers rejected by measurement, not opinion

A subprocess-spawn audit found no dominant offender (`sys` is diffuse across 1 296 tests; 409 `python3` calls over ~30 files, only 13 `bun`), and the qmd e2e suite had no embedding work to shrink because `qmd update` never embeds (`qmd embed` is a separate command it does not call) — its ceiling was ~4 s. Both were reported as no-target instead of being padded with churn. When measuring here, treat sub-10 s spreads as noise: run-to-run variance on this workstation was ±10 s.
