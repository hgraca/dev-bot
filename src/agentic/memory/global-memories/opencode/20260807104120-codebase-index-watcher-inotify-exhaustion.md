---
date: 2026-08-07
updated: 2026-08-17
keywords: ["opencode", "codebase-index", "inotify", "ENOSPC", "graphify"]
trigger-on: ["codebase-index-config", "inotify-watcher-exhaustion"]
---

## Codebase-index file watcher exhausts inotify limit by watching all directories

`ENOSPC: no space left on device` from `[codebase-index] Watcher` is inotify watch exhaustion, not disk space. The codebase-index watcher (chokidar) adds an inotify watch per file for every non-ignored path under the project root. `include`/`exclude` config only gates what gets _indexed_, not what gets _watched_ — so `graphify-out/cache/ast/` (80K+ files) still gets a watch per file. Multiple OpenCode instances compound the problem since each spawns its own MCP process.

What actually stops the watcher is chokidar's `ignored` filter. In `opencode-codebase-index` (verified 0.22.4 and 0.23.0) it is built from ONLY:

- hardcoded defaults (`node_modules`, `.git`, `dist`, `build`, `.opencode`, `.codebase-index`, `.*`, `**/*build*/**`, ...)
- the project's `.gitignore` (read by `createIgnoreFilter`)
- hidden/"build" path segments

It does NOT read:

- `.git/info/exclude` (where graphify's init writes `graphify-out/`)
- the config `exclude` list (only used for indexing, never for watching)

**Fix**: add `graphify-out/` to `.gitignore` (not just `.git/info/exclude`), then restart the MCP server/session — the ignore filter is built once at watcher startup. The config `exclude` entry alone does nothing for the watcher; bumping `fs.inotify.max_user_watches` is only a mitigation, not a fix.
