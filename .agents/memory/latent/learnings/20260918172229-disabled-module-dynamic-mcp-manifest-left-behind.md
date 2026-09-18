---
date: 2026-09-18
keywords: ["mcp", "module-disable", "dynamic-manifest", "reinit", "opencode"]
---

# A disabled module's dynamic MCP manifest was left behind — and re-registered every reinit

## The trap

`devbot reinit` after disabling a module did not remove the module's **dynamic runtime MCP manifest**, so the server stayed live.

A module init may emit `.opencode/<name>.mcp.json` (opencode) or `.claude/<name>.mcp.json` (claudecode) instead of a canonical `mcp.json` — jetbrains does, because its IDE port is only known at init time (ADR `20260822224308-harness-agnostic-module-init`). Three things made a disable ineffective:

- **The file is a regular file, not a symlink.** `_reset_symlinks_in_dir` only deletes symlinks, so it never touched the manifest.
- **The disabled-module prune keyed on a canonical `mcp.json` / `plugin.opencode.json`** — files jetbrains declares neither of. So there was no server key to remove from `opencode.jsonc` either.
- **`_register_dynamic_mcps` / `_wire_mcp` had no disabled-module gate**, so every reinit merged the leftover manifest back in. `bin/init.sh` skips a disabled module's `init.sh`, so the manifest was *left*, never recreated — but the ungated merge re-registered its server anyway.

Observed symptom: `jetbrains: false` in both configs, yet `.opencode/jetbrains.mcp.json` and the `jetbrains` key in `opencode.jsonc` persisted, and reinit was not idempotent for that project.

## The fix (c82e09f2)

Ownership of a dynamic manifest follows the `<name>.mcp.json` / `<name>-<detail>.mcp.json` convention (datasources emits the prefixed form), encoded once in `_devbot_manifest_owner_disabled` (`src/_shared/functions.sh`):

- both harness resets prune a disabled module's dynamic manifests; opencode reset also drops the server key(s) each registered from `opencode.jsonc` (that merge is append-only, never regenerated — claudecode's `.mcp.json` is regenerated from scratch, so it needs no key removal).
- both harness inits skip manifests owned by a disabled module, so a bare `devbot init` (no preceding reset) cannot resurrect the server either.

## Rule for future module work

A module that emits a dynamic runtime manifest gets disable-cleanup for free **only if it follows the `<module>.mcp.json` naming** — the harness maps a manifest back to its module solely by that filename, so a differently-named manifest is invisible to both the prune and the gate. The rule is exact-or-hyphen-prefixed: `tools` would claim `tools-mcp.mcp.json`, so a module name that is a hyphen-prefix of another module's would collide (none today).
