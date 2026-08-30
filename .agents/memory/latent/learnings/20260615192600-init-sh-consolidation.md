---
date: 2026-06-15
keywords: ["devbot", "init.sh", "refactoring"]
---

# bin/init.sh — four separate agentic-module loops consolidated into one

`bin/init.sh` previously had 4 separate places iterating agentic modules (`_run_inits` init.sh, `_wire_external_modules` external wiring, `_register_module_mcp_servers` MCP, `_link_memory_folders` memory), each reparsing `disabled_modules` via its own call to `_devbot_get_disabled_modules`. Two bugs: `_wire_external_modules` called `external-modules/init.sh` with NO disabled check at all, and `external-modules/init.sh` ran twice (once via `_run_inits` inner `init_modules` loop, once via `_wire_external_modules`). Refactored to parse `disabled_modules` ONCE upfront, then a single unified loop through `src/agentic/*/` gates all three actions (init.sh, MCP registration, memory linking) behind one disabled check. Reduced 429 → 334 lines, eliminated 4 separate functions, removed 2 redundant `_devbot_get_disabled_modules` calls.
