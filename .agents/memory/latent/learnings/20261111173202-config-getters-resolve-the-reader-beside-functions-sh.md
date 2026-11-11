---
date: 2026-11-11
keywords: ["devbot", "read_jsonc", "DEV_BOT_ROOT", "bats", "config"]
aliases: ["shared_dir reader", "_devbot_get_config sandbox", "reader path"]
see: ["learnings/20261016234501-module-up-sh-failure-is-swallowed.md"]
---

# Config getters resolve `read_jsonc.py` beside `functions.sh`, not under `DEV_BOT_ROOT`

`_devbot_get_config` and `_devbot_get_workspace_config` used `${DEV_BOT_ROOT}/src/_shared/read_jsonc.py`. Module BATS fixtures routinely point `DEV_BOT_ROOT` at a bare temp root that holds only the config and the module scripts — no `src/_shared` — so every scalar read there failed silently and returned its built-in default (harness → `opencode`, `devbot_dir` → `.agents`, `workspace.*` → empty). A test could look green while the value under test never reached the code.

Both getters now resolve the reader from `$(dirname "${BASH_SOURCE[0]}")`, matching `_devbot_get_disabled_modules`, `_devbot_get_codebase_provider` and `_devbot_get_memory_search_provider`, which had always done that for exactly this reason. Production is unaffected (`DEV_BOT_ROOT` is where `functions.sh` lives), and sandboxed fixtures see the real project and global configs again.

## Testing consequence

A sandbox no longer needs its own `src/_shared/read_jsonc.py` copy for the getters to work — `src/_shared/tests/*` fixtures that still copy it are harmless, not required. What a sandbox _does_ still need, when it exercises harness selection, is a `src/harnesses/` directory tree: `_devbot_get_disabled_modules` lists it beside the library, and the canonical `opencode`/`claudecode` pair covers a missing one.
