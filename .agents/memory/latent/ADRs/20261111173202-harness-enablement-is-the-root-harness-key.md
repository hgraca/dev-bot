---
date: 2026-11-11
keywords: ["devbot", "harness", "modules", "enablement", "single-toggle"]
aliases: ["harness selection", "modules map harness", "two harness toggles"]
see: ["ADRs/20261007205255-machine-wide-module-lifecycle-enablement-independent.md"]
---

## Harness enablement is the root `harness` key alone

Harness wiring used to have two independent switches: the root `harness` scalar chose which `start.sh` launched, while `modules.opencode` / `modules.claudecode` separately gated that harness's `init.sh`, memory links, MCP registration, `up.sh` and `list` rows. Neither consulted the other, so the shipped default (`modules.claudecode: false`) made `harness: claudecode` launch against a tree that was never wired, and a `modules` entry could disable the very harness in use.

`_devbot_get_disabled_modules` (`src/_shared/functions.sh`) is now the single decision point: it drops any module key naming a directory under `src/harnesses/` and appends every harness except the one `_devbot_get_harness` selects — the canonical `opencode`/`claudecode` pair unioned with whatever `src/harnesses/` holds, so a partial install still disables the other one. Exactly one harness is enabled; a harness name in the global or project `modules` map is silently ignored; there is no way to express "no harness". Every consumer (`_init_modules`, `_run_service_scripts`, compose discovery, memory linking, MCP registration, the env-var check, both harness `reset.sh` scripts, `devbot list`) inherits the rule without edits, and `install`/`update`/`uninstall` keep bypassing it with `--all`.

Two consequences are deliberate and documented in `docs/configuration.md` §`harness`: switching harness leaves the previous harness's tree in place because its reset is skipped while it is unselected (select it again and reinit to clean it, or `devbot uninstall`), and module-owned artifacts in the unselected tree must not be written or pruned — `bin/init.sh` resolves `opencode.jsonc` only when opencode is selected (`_resolve_opencode_config`), and `codebase-index/reset.sh` and `netsuite/init.sh` gate their cleanup on the selected harness.
