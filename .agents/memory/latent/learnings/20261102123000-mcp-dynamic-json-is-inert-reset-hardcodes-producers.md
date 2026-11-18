---
date: 2026-11-02
keywords: ["mcp.dynamic.json", "opencode", "reset", "dynamic-manifest", "devbot"]
---

# `mcp.dynamic.json` is still mostly documentation-only; reset hardcodes the producer list

`docs/mcp-config.md` and `docs/create-a-module.md` say a module declares the
server-key prefixes it owns in `mcp.dynamic.json`, and that opencode reset
prunes a disabled emitter's keys by that declaration.

- `src/harnesses/opencode/reset.sh` (and `opencode-v2/reset.sh`)
  `_is_dynamic_manifest_producer` still hardcodes `aws|datasources|jetbrains|netsuite`.
- `_devbot_manifest_owner_disabled` (`src/_shared/functions.sh`) infers
  ownership from the manifest filename (`<module>.mcp.json` /
  `<module>-<detail>.mcp.json`), **not** from `mcp.dynamic.json` — so a
  manifest filename must keep the module name even when its server keys use a
  shorter prefix.
- The declaration **is** now read in the one place it was most needed: the
  orphan-key fallback of both opencode resets matches the module name **plus**
  every prefix in `mcp.dynamic.json` (this is how a disabled datasources module
  still prunes a `ds-<source>` key after its `datasources-<source>.mcp.json`
  manifest is gone). When the manifest exists, reset reads the keys from the
  manifest itself.

Consequence: a new dynamic emitter still gets no disable-cleanup unless its name
is added to the reset case, and it must still name its manifest after the
module. Keep the hardcoded list and the docs in sync, and declare a short
server-key prefix here when the module wires keys that differ from its name.
