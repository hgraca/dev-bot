---
date: 2026-06-14
keywords: ["devbot", "module", "wiring", "plugin", "symlink"]
---

# Module wiring requires 3 integration points beyond file creation

Creating a new module (e.g. `format-json`) under `src/agentic/` requires manual wiring of 3 integration points after creating the module anatomy:

1. **Skill symlink** — `ln -sf $(pwd)/src/agentic/<module>/skills $(pwd)/.opencode/skills/devbot/<module>` so the skill is discoverable via OpenCode's `available_skills` list
2. **Plugin symlink** — `ln -sf $(pwd)/src/agentic/<module>/hooks/opencode/<hook>.ts $(pwd)/.opencode/plugins/<hook>.ts` so the OpenCode plugin hook is loadable at runtime
3. **Config registration** — add the plugin path string to the `"plugin"` array in `opencode.jsonc`

These are not automated by `install.sh` — the format-md `install.sh` only verifies python3. The symlinks and config registration must be done manually or via `init.sh` (which format-json's `init.sh` does for the plugin registration only, not the symlinks).
