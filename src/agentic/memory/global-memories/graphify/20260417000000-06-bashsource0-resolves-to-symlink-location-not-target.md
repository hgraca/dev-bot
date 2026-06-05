---
date: 2026-04-17
keywords: ["graphify", "graph"]
---

## `BASH_SOURCE[0]` resolves to symlink location, not target

When a script is symlinked (e.g. `.opencode/graphify-serve.sh -> src/tools/graphify/serve-wrapper.sh`), `BASH_SOURCE[0]` resolves to the symlink path, not the target. Path traversal like `$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)` gives the wrong root. Fix: inject `$DEVBOT_ROOT` as an environment variable via the MCP config `{file:storage/secrets/devbot-root}` pattern instead of computing it from the script path.
