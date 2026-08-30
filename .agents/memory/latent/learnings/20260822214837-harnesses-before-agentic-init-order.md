---
date: 2026-08-22
keywords: ["opencode", "init", "harness", "agentic", "opencode.jsonc"]
---

# Harnesses init must run before agentic modules in bin/init.sh

SUPERSEDED by `ADRs/20260822224308-harness-agnostic-module-init.md`. The "harnesses before agentic" order was a workaround for module init.sh scripts editing `opencode.jsonc` directly (codebase-index's `_upsert_opencode_plugin`, jetbrains' MCP registration). The real fix made modules harness-agnostic (declare manifests, harnesses apply), so the order is back to tools → agentic → harnesses. `config_file` is still re-detected after the harness phase so the unified MCP registration loop sees the freshly written `opencode.jsonc`.
