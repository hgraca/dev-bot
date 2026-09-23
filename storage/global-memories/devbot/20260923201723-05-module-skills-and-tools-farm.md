---
date: 2026-09-23
keywords: ["devbot", "module", "skills", "tools", "mcp-meta"]
trigger-on: ["devbot-module-tool-wiring", "devbot-module-skill-wiring"]
---

## How a dev-bot module's skills and tools reach the harness

`_link_modules` (`src/tools/devbot-cli/functions.sh`) walks `src/agentic/*/` and for each enabled module runs `_link_skills` and `_link_tools`. `_link_skills` symlinks the module's **whole `skills/` directory** to `.agents/skills/devbot/<module>` — so a module carries one skill at `skills/SKILL.md`, and the skill *name* the harness reports comes from the frontmatter `name:`, not the directory. `_link_tools` symlinks every `tools/**/*.mcp.sh` (find `-maxdepth 3`, so `tools/<name>/<name>.mcp.sh` works) into `.agents/tools/`, where the `tools-mcp` server discovers it by running `<script> mcp-meta` and parsing the JSON it prints; a tool whose `mcp-meta` fails or omits `name`/`description` is silently skipped. Consequences: adding a module tool or skill needs **no core change** (there is no registry to edit), the `mcp-meta` branch must sit before any dependency check or `exec`, and module enablement is opt-*out* — a module is disabled only when its effective config value is `false`.
