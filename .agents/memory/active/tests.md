---
tags: [bootstrap, tests, performance]
description: How to write, organise and split tests so `make test` stays fast — the cost model, the rules, and the measurements behind them
---

## Tests — keep the suite fast

`make test` is the gate every change passes through, and its wall clock is what
decides whether a developer runs it or skips it. A test that costs 20 s of a
5-minute suite is a design decision, not a detail: budget for it.

### The cost model (measured, 2026-11)

The BATS runner parallelises **across files only** (`--no-parallelize-within-files`),
so:

```
wall ≈ (total per-test work ÷ jobs) + (files × ~0.4 s) + tail
```

Three consequences, each measured on this repo:

- **One long file is a floor.** `opencode-v2/tests/init_tests.bats` at 12.8
  minutes set the wall clock for the whole suite; splitting it into four themed
  files took it to 2 minutes and the suite from 24 to 6.
- **More lanes stop helping.** 8 jobs is faster than 12 (6m23s vs 6m54s, +47%
  CPU) and 16 saturates the box: heavy tests are themselves multi-core (qmd,
  php, java, python). Do not raise `--jobs`; raise throughput by doing less work.
- **Per-file overhead is real.** ~0.4 s × 229 files ≈ 1.5 min. Splitting pays
  only while a file is a floor (roughly >2 minutes); below that it is net cost.

### The first rule: one run per distinct input

A test that runs the tool under test once and asserts one property costs a full
run for that assertion. When several tests share the same input, run it once:

```bash
scenario default                       # one real run, shared by this file
scenario stale-link _seed_stale_link   # one run per distinct pre-state
scenario_copy default                  # this test's own copy: it mutates first
```

The mechanism is `src/_shared/tests/lib/scenario.bash`; each file supplies one
builder that writes the input and runs the tool, so the whole scenario set is
visible in one place. Applied to `init_tests.bats` and `memory-smoke_tests.bats`:
~60 runs → ~45, and 37 → 12, with identical assertions.

Rule of thumb: if a file runs the same command more than three times on the same
input, make that input a scenario.

### What must NOT be shared

- **A snapshot is not a substitute for the behaviour under test.** If a test's
  subject is init's effect on a pre-state (a stale link, a legacy config, a
  disabled module), it seeds that state and runs for real. Sharing those would
  assert on a jpeg of a previous run and stay green after the code broke.
- Tests whose _only_ difference is the assertion share happily; tests whose
  input differs do not. Check before refactoring: `datasources` is 84/93 tests
  configuring distinct inputs — nothing to share, its cost is real coverage.

### Organising a test file

- One theme per file. A file is a scheduling unit, so a file mixing cheap
  assertions with two-minute runs cannot be overlapped with anything.
- Above ~2 minutes of run time, split by theme into separate files that `load`
  the same helper — `datasources_{render,init,up,reload}_tests.bats`,
  `init_{config,plugins,skills,nested}_tests.bats`.
- Setup, teardown and fixtures go in `<module>_test_helper.bash` loaded with
  `load 'x_test_helper'` (see `refactor/tests/refactor_test_helper.bash`).
  Never copy fixtures into each split file.
- Keep the test count and the assertions when splitting: move ranges verbatim,
  and verify the total — `grep -c '^@test'` across the new files must equal the
  original file's count.

### Writing a new test

- **Assert on output, not on a re-run.** If the assertion needs what the tool
  printed, capture the run's output (`scenario_output <name>` sets
  `$output`/`$status`) instead of running it again.
- **Idempotency tests are exempt** and must run the command twice — that is the
  property. Use `scenario_copy` so the second run starts from a real first run.
- **Stay hermetic:** `mktemp -d`, `BATS_TEST_TMPDIR` for per-test state,
  `BATS_FILE_TMPDIR` for per-file state, and stub `docker`/`qmd`/network. A test
  that reaches a real service is slow _and_ flaky.
- **Never mutate a tracked file.** `docs_tests.bats` swaps a checked-in script
  for a mock and restores it in `teardown_mock`; an interrupted run leaves the
  mock in the repo. Copy instead, or restore from a `trap`.
- **Batch interpreter launches.** A `python3` start is ~30-60 ms and a fork is
  ~4 ms: per-module `basename`, `echo | grep -Fxq` and one-python-per-server
  loops dominate real runtime. Resolve once, then pass the value down.
- **Don't sleep to prove liveness.** Size any timer window against the slowest
  observed run; a fixture that passed alone and fails in the suite is a timing
  bug (see the `_live_session` lesson).

### Before you commit a test change

```bash
bats -T <file>                    # per-test timings; a 20 s test needs a reason
bats <file>                       # green
make test                         # the wall clock still fits
```

Splitting or refactoring tests is verified by the same two facts as any other
change: the assertions still fail when the behaviour breaks, and the count is
unchanged.
