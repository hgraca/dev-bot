---
date: 2026-06-15
keywords: ["shell", "devbot", "DEV_BOT_ROOT", "MODULE_DIR"]
---

## Trust script-relative paths over env vars set by shared libraries

`DEV_BOT_ROOT` in `src/_shared/functions.sh:27` is set to `src/` (one level too shallow) when the script is sourced outside of `bin/*.sh` lifecycle scripts — because the `DEV_BOT_ROOT` resolution at that line only works correctly when pre-set by bin scripts. Modules that rely on `DEV_BOT_ROOT` for `storage/` directory creation end up with paths like `src/storage/<name>/` instead of the project root. Fix: compute the project root directly from `MODULE_DIR` (derived from `BASH_SOURCE`) using relative navigation — e.g. `cd "${MODULE_DIR}/../../.." && pwd`. This is robust regardless of how the script was invoked or sourced.
