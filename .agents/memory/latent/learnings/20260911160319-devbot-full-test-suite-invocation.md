---
date: 2026-09-11
keywords: ["devbot", "bats", "make", "test", "shell"]
---

# Running dev-bot's full test suite (and BATS directly)

`make test` is the entry point and runs three stages in sequence: BATS over `src/` and `bin/`, then `bun test src/`, then a `python3 -m unittest` loop over `src/**/test_*.py` — currently 1 713 tests (1 296 / 116 / 301) in ~88 s wall, against ~341 s when BATS ran serially. BATS is ~99% of that time and is parallelised: the Makefile resolves the runner (GNU `parallel`, else `rush` via `--parallel-binary-name rush`, else a `WARN:` and a serial fallback), caps jobs at 8, runs `bin/` first, and honours `DEV_BOT_TEST_JOBS` (`1` forces serial). GNU `parallel`/`rush` is a documented dev prerequisite — see README, `## Development`. A stuck BATS run is therefore now ~90 s, not the 10 minutes this note originally warned about.

Invoking a single BATS file directly still requires the shared libs on the path or `bats_load_library bats-support`/`bats-assert` fail with "Could not find library": use `BATS_LIB_PATH="$(npm root -g)" bats <file>.bats`. BATS discovers tests recursively, so a new `src/agentic/<mod>/tests/*.bats` is picked up automatically — no manifest to update — while non-`*.bats` helpers such as `bin/tests/update_helpers.bash` (pulled in with `load`) are never collected as tests.
