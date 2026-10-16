---
date: 2026-10-16
keywords: ["up.sh", "run_service_scripts", "lifecycle", "guard", "devbot"]
aliases: ["module up script failure", "up script cannot abort start"]
---

# A module `up.sh` cannot refuse a `devbot` start — its failure is swallowed

`_run_service_scripts` (`src/_shared/functions.sh`) runs each module's lifecycle script as `if bash "${script}" "$@"; then … else _skip "…had issues"; failed=$((failed + 1)); fi`, and its tail is an `echo`/`_ok` that always returns 0. So a module `up.sh` that exits 1 prints "had issues" and the function still reports success — `bin/up.sh` exits 0, and `cmd_harness` (`bin/devbot`) only aborts on `bin/up.sh`'s own exit code. Verified against a sandbox module whose `up.sh` exits 1: `_run_service_scripts` returned 0.

## Consequence for guards

A hard refusal (e.g. "this host version is unsupported") must live in the harness `start.sh`, whose non-zero exit becomes `devbot`'s exit code. Putting it only in `up.sh` yields a warn-and-continue: the message appears, the launch proceeds.

`MODULE_SCRIPT_FAILED` is not the escape hatch — it is exported by the single-module helper `_run_module_script` and consumed only by `bin/update.sh`; `_run_service_scripts` neither sets nor propagates it.

## Harness-level `up.sh` scripts are never module-gated

`_run_service_scripts` scans `src/tools`, `src/agentic` and `src/harnesses`, skipping a directory whose name is a key in the `modules` map set to `false`. `opencode` is **not** a key in that map (only `claudecode` is), so `src/harnesses/opencode/up.sh` runs on every `devbot up` / `make up` regardless of the configured harness. A harness-scoped check inside such a script must gate itself on `_devbot_get_harness "${1:-.}"`, or a machine configured for the other harness that merely has that binary on disk gets a spurious message.

## Testing note

BATS fixtures for a script that resolves config need the sandbox root to carry `src/_shared/read_jsonc.py` — `_devbot_get_config` resolves the reader from `${DEV_BOT_ROOT}`, so a bare sandbox root silently yields an empty value and falls through to the default (a passing test that proves nothing).
