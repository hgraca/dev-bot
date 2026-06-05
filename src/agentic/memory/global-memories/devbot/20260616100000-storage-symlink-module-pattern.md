---
date: 2026-06-16
keywords: ["devbot", "storage", "symlink", "module-pattern", "init.sh"]
---

## Storage + Symlink Module Pattern

When a module needs large binary assets (MCP server binaries, external skill directories), store them under `storage/<module>/` in devbot root and symlink them into projects during `init.sh`. This avoids per-project duplication and ensures single-source-of-truth for versioned assets.

Pattern: `install.sh` downloads assets into `$DEV_BOT_ROOT/storage/<module>/bin/` (or `skills/`, etc.). `init.sh` creates symlinks from the project's `.opencode/` to the storage paths. `mcp.opencode.json` uses relative project paths (e.g. `.opencode/signoz-mcp-server`) that resolve through the symlinks created by init.sh.

Critical ordering: `bin/init.sh` runs module `init.sh` BEFORE MCP auto-registration from `mcp.opencode.json`. This guarantees symlinks exist before MCP config references them. Graphify uses a similar pattern via `storage/secrets/graphify-python` but only for a single file — the signoz module generalizes this to arbitrary directory structures.
