---
date: 2026-08-22
keywords: ["devbot", "harness", "module", "manifest", "opencode"]
see: ["ADRs/20260822115731-manifest-driven-hooks-architecture.md"]
---

## Module init.sh must be harness-agnostic: declare manifests, harnesses apply

Agentic module `init.sh` scripts must not edit harness config directly (`opencode.jsonc`, `.mcp.json`). They declare integration needs in manifests and the harnesses apply them: `mcp.opencode.json` / `mcp.claudecode.json` for static MCPs, `plugin.opencode.json` for opencode plugins (applied by the opencode harness `_link_module_plugins`), and a runtime `.opencode/<name>.mcp.json` / `.claude/<name>.mcp.json` manifest for dynamic values (e.g. jetbrains' runtime-detected IDE port, applied by `_register_dynamic_mcps` / `_wire_mcp`). This extends the existing manifest-driven-hooks pattern to MCP/plugin registration. Rationale: direct config editing made module init depend on the harness having run first — codebase-index failed on a missing `opencode.jsonc`, jetbrains silently skipped registration — forcing the wrong tools → harnesses → agentic order. With modules harness-agnostic the order is tools → agentic → harnesses; the static jetbrains mcp manifests (unresolved `__MCP_PORT__`/`__PROJECT_DIR__` placeholders, stale hardcoded port) were deleted in favour of the runtime manifest.
