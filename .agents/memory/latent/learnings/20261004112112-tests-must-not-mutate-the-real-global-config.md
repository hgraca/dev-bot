---
date: 2026-10-04
keywords: ["devbot", "global-config", "test-isolation", "bats"]
aliases: ["tests clobbered .devbot.global.jsonc", "DEV_BOT_GLOBAL_CONFIG"]
---

# Tests must not mutate the developer's real .devbot.global.jsonc

`bin/tests/commands_tests.bats` overwrote the real global config to toggle a disabled
module and restored it in `teardown`, while `devbot init` (`bin/init.sh` step 7 →
`add_project.py`) writes the real config too. Run with BATS `--jobs`, the setup/
overwrite/restore of one file races another file's write and the config is left
clobbered — observed 2026-10-04 reduced to `{modules:{websearch:false},
projects:[storage/test]}`, every other key lost (no backup; `install.sh` skips an
existing config and there is no dist-merge recovery).

Fix: a `DEV_BOT_GLOBAL_CONFIG` env override, resolved once in `_devbot_global_config()`
(`src/_shared/functions.sh`) and honoured by every read/write of the global config
(`bin/init.sh`, `module.sh`, external-modules scripts, `list-projects.mcp.sh`, the
wiring-sha helpers). Config-mutating tests point it at a `mktemp` copy seeded from the
real file, so the real one is never touched — verify with a sha before/after the run.
Two gotchas: (a) files that compute the path *before* sourcing `functions.sh` (e.g.
`module.sh:20`) must use the inline `${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}`
form, not the resolver; (b) BATS tests that `awk`-extract a subset of `functions.sh`
into a sandbox (`up_compose_opts`, `up_config_baseline`, `reinit_dirty_flag`) must also
extract `_devbot_global_config`.
