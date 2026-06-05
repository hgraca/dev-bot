---
date: 2026-05-20
keywords: ["shell", "bash", "pipefail", "soft-failure", "install-script"]
---

## Wrap fallible commands in if/else under set -euo pipefail

Under `set -euo pipefail`, any command that exits non-zero aborts the script immediately. Install scripts that intend soft-failure (warn and continue) must wrap such commands in an `if/else` block rather than running them bare. Example: `uv tool install 'litellm[proxy]'` run bare will abort the script on failure; wrapping it as `if uv tool install 'litellm[proxy]'; then ... else warn "..."; fi` preserves the intended fallback behaviour. Apply this pattern to every external tool invocation in install scripts where failure should be non-fatal.
