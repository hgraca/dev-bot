---
date: 2026-05-20
keywords: ["shell", "pipefail", "set -e", "fallthrough", "error handling"]
---

## Use if/else for fallthrough under set -euo pipefail, not bare commands

Under `set -euo pipefail`, any command that exits non-zero aborts the script immediately. When you need a command to fail gracefully and fall through to an alternative path (e.g. `docker pull` failing → try `uv` instead), wrap it in an explicit `if/else` block rather than using `|| true` or a bare call. Pattern: `if docker pull image; then secrets.write "method" "docker"; else warn "pull failed"; fi` — then continue to the uv block. A bare `docker pull image || warn "..."` still falls through but a bare `uv tool install pkg` after it will abort on failure without reaching the soft-failure warn. Apply the same `if/else` wrapping to every command in the fallback chain that must not abort the script.
