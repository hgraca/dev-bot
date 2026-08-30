---
date: 2026-06-12
keywords: ["devbot", "documentation", "modules", "docs"]
---

## Consolidated all module documentation into single docs/module.md

Replaced the 14 individual `docs/modules/*.md` per-module files with a single comprehensive `docs/module.md` that documents all three module categories in one place: agentic internal (23 modules), tools (5 modules), and agentic external (registered addyosmani + available karpathy-guidelines). The old `docs/module.md` only covered the external module CLI. The new doc adds full tables with skills counts, tools, hooks, MCP servers, and descriptions verified against actual on-disk modules. The empty `docs/modules/` directory was removed. `README.md` was updated to point to the single consolidated doc.
