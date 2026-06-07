---
date: 2026-06-11
keywords: ["devbot", "init", "tools", "symlink", "_link_tools", "watermark-session", "opencode"]
---

# memory module tools use nested directory structure, missed by `_link_tools`

The memory module (`src/agentic/memory/tools/`) organizes tools under subdirectories per tool: `tools/<name>/opencode/<name>.ts` and `tools/<name>/<name>.sh`. This is different from every other module (agent-communication, format-md, tree), which place the `.ts` file directly at `tools/<name>.ts`.

The `_link_tools` function in `src/tools/opencode/init.sh` uses `find "${tool_dir}" -maxdepth 1 -type f` to discover tool `.ts` files — it only finds files directly inside `tools/`, never nested subdirectories. This means `devbot init` never creates symlinks for `watermark-session.ts` or `search-memories.ts`.

Affected tools:

- `watermark-session` — `.ts` at `tools/watermark-session/opencode/watermark-session.ts` (NOT linked)
- `search-memories` — `.ts` at `tools/search-memories/opencode/search-memories.ts` (NOT linked)

Fix: move the `.ts` files to `tools/<name>.ts` (flat, matching convention) and update their `Bun.spawn` script paths to point into the subdirectory, or alternatively update `_link_tools` to discover `.ts` files one level deeper.
