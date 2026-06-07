---
date: 2026-08-06
keywords: ["devbot", "harnesses", "directory-structure"]
see: ["ADRs/20260806131000-generic-module-script-runner.md"]
---

## `src/harnesses/` directory separates harness modules from tools

Created `src/harnesses/` as a third module category alongside tools and agentic. Moved `src/tools/opencode` and `src/tools/claudecode` into `src/harnesses/`. All lifecycle scripts (install, update, init, uninstall, reinit) and the unified MCP/memory/init passes in init.sh now iterate `src/{tools,agentic,harnesses}` uniformly. The generic `_run_module_script` pattern made this trivial — each script just gets one additional call. `up.sh` already used `find src/` so harnesses were auto-discovered. Docker service discovery remains `src/tools`-only (correct — Docker services live only under tools).
