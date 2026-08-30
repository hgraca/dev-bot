---
date: 2026-06-14
keywords: ["devbot", "external-modules", "module-anatomy", "merge_modules_jsonc"]
---

# External-modules.json per-module declaration pattern

Established `external-modules.json` as a new component in the agentic module anatomy — analogous to `mcp.opencode.json` for MCP servers. Modules that require external git repositories (skills, agents, commands) declare them via a `src/agentic/<module>/external-modules.json` file matching the `.devbot.jsonc` `modules` key format.

On `bin/up.sh`, `_rebuild_external_module_config()` scans all enabled modules for these files and merges their entries into the root `.devbot.jsonc` `modules` config idempotently via `merge_modules_jsonc.py`. Disabled modules' declarations are skipped.

## Gotcha: comma placement in JSONC merge

When the `merge_modules_jsonc.py` script creates a new `modules` section in a JSONC file (no existing `"modules"` key), it must insert before the root object's closing `}`. The initial implementation placed a trailing comma on the new section (`...},\n`) and omitted a separator comma before the new section — producing corrupt JSON when other fields precede it.

**Fix**: The `pre_close` (content before closing `}`) is rstripped and checked: if it doesn't end with `{` (empty root) or `,` (existing trailing comma), a comma is prepended before the new `modules` entry. The entry itself has no trailing comma.
