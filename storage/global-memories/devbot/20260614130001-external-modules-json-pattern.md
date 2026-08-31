---
date: 2026-06-14
keywords: ["devbot", "external-modules", "module-pattern"]
---

## external-modules.json Module Pattern

Only the `external-modules` module itself has `external-modules.json` (`src/agentic/external-modules/external-modules.json`). No other module (graphify, etc.) declares one.

The file declares external git repos to wire into the project's `.opencode/` directories. Each entry has:

- `"url"`: git clone URL (HTTPS or SSH)
- `"paths"`: maps destination type (`"agents"`, `"skills"`, `"memory"`) to the relative path inside the repo. For memory, it can be a nested object mapping filenames to destinations (e.g. `"CLAUDE.md": "bootstrap/karpathy-instructions.md"`).

The `init.sh` of external-modules reads `.devbot.jsonc` modules config, clones repos to `vendor/`, then symlinks each module's paths into the project's `.opencode/agents/` and `.opencode/skills/`, and wires memory files into `.ai/devbot/memory/`.

External modules are processed in `bin/init.sh` by the `_wire_external_modules()` function, which delegates to `src/agentic/external-modules/init.sh`.
