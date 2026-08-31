---
date: 2026-08-22
keywords: ["shell", "bats", "bats_load_library", "npm"]
trigger-on: ["bats-npm-root-load"]
---

## Use bats_load_library + BATS_LIB_PATH, not `load "$(npm root -g)/..."` per test

In bats, `load "$(npm root -g)/bats-support/load.bash"` inside `setup()` spawns `node` twice per test (once per `npm root -g` command substitution) just to resolve the global node_modules path — ~0.7s/test × hundreds of tests. bats 1.10+ ships `bats_load_library <name>`, which resolves from the `BATS_LIB_PATH` env var and dedupes across tests (no subprocess). Set `BATS_LIB_PATH="$(npm root -g)"` once in the Makefile test target (or `export` it before running bats directly), then replace the two `load` lines with `bats_load_library bats-support` and `bats_load_library bats-assert`. A `local bats_lib="$(npm root -g …)"` fallback that then does `load "${bats_lib}/…"` has the same per-test spawn cost and can be dropped entirely. Measured: a 47s suite dropped to ~7s, a 29s suite to ~12s.
