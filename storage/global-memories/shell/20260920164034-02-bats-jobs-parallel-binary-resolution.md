---
date: 2026-09-20
keywords: ["shell", "bats", "parallel", "rush", "jobs"]
trigger-on: ["bats-parallel-jobs"]
---

## `bats --jobs` needs GNU parallel or rush named explicitly, and rejects `--jobs 1`

`bats --jobs N` drives a parallel binary whose name defaults to `parallel` and changes only via `--parallel-binary-name`; bats never auto-detects shenwei356's `rush`, so on a rush-only machine `bats --jobs` fails with `parallel: command not found` plus `Executed 0 instead of expected N tests` — you must pass `--parallel-binary-name rush`. A non-GNU `parallel` also satisfies `command -v parallel` while being flag-incompatible (Debian/Ubuntu ship `moreutils`' one), so probe for the real thing with `parallel --version | grep -q 'GNU parallel'` rather than relying on `command -v`. Two further constraints: `--jobs 1` is rejected alongside `--no-parallelize-within-files` ("requires at least --jobs 2"), so a request for serial must route to a plain serial invocation rather than to `--jobs 1`; and `--no-parallelize-within-files` is the flag that keeps each file's tests on one process when suites share per-file state. Expect far less than N-fold speedup — a suite of many small, I/O-bound tests measured only ~3-3.5x at 8 jobs, and 16 jobs was slower than 8.
