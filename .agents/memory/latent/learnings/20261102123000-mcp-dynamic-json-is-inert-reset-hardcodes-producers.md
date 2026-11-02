---
date: 2026-11-02
keywords: ["mcp.dynamic.json", "opencode", "reset", "dynamic-manifest", "devbot"]
---

# `mcp.dynamic.json` is documentation-only; reset hardcodes the producer list

`docs/mcp-config.md` and `docs/create-a-module.md` say a module declares the
server-key prefixes it owns in `mcp.dynamic.json`, and that opencode reset
prunes a disabled emitter's keys by that declaration. No code reads those files.

- `src/harnesses/opencode/reset.sh` `_is_dynamic_manifest_producer` hardcodes
  `aws|datasources|jetbrains`.
- `_devbot_manifest_owner_disabled` (`src/_shared/functions.sh`) infers
  ownership from the manifest filename (`<module>.mcp.json` /
  `<module>-<detail>.mcp.json`), not from `mcp.dynamic.json`.
- The three shipped `mcp.dynamic.json` files (`aws`, `datasources`,
  `jetbrains`) are inert.

Consequence: a new dynamic emitter gets no disable-cleanup unless its name is
added to the reset case, and the docs misstate the mechanism. Keep the
hardcoded list and the docs in sync until the declaration is actually wired.
