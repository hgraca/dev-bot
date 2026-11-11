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

## Harness-level `up.sh` scripts are gated by the selected harness

`_run_service_scripts` scans `src/tools`, `src/agentic` and `src/harnesses`, skipping a directory whose name is in the disabled set. Harness enablement is the root `harness` key alone (`_devbot_get_disabled_modules` appends every harness except the selected one and ignores harness names in the `modules` maps), so only the configured harness's `up.sh` runs. A harness-scoped check inside such a script is still worth keeping for a direct invocation, but it is no longer load-bearing for `devbot up` / `make up`.

## Testing note

The config getters (`_devbot_get_config`, `_devbot_get_workspace_config`) resolve `read_jsonc.py` beside `functions.sh`, not under `${DEV_BOT_ROOT}`, so a bare sandbox root no longer hides a project or global config from them. A sandbox that exercises `_devbot_get_disabled_modules` still needs its own `src/harnesses` directory to observe harness selection, or it falls back to the canonical `opencode`/`claudecode` pair.
