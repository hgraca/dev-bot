---
date: 2026-04-12
keywords: ["opencode", "tool"]
---

## `{file:path}` secret paths are relative to the project root

opencode resolves `{file:...}` paths relative to the directory where `opencode.jsonc` lives. Since projects get a symlink `<proj>/opencode.jsonc → <devbot-root>/storage/opencode.jsonc`, the secret path in the dist config (`src/tools/opencode/opencode.dist.jsonc`) must be `storage/secrets/<name>` (relative to the project root, not the DevBot root).
