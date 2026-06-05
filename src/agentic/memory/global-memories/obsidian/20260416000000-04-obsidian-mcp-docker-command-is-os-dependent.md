---
date: 2026-04-16
keywords: ["obsidian", "mcp", "docker"]
---

## Obsidian MCP Docker command is OS-dependent

`src/tools/obsidian/install.sh` emits different MCP configs per OS:

- **Linux**: `--network host` + `https://127.0.0.1:27124`
- **macOS**: default bridge + `https://host.docker.internal:27124`
  The local `opencode.jsonc` copy is written at install time from the dist file and is OS-specific.
