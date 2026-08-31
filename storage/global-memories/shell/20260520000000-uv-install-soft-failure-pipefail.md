---
date: 2026-05-20
keywords: ["shell", "uv", "pipefail", "soft-failure", "install-script"]
---

## Wrap fallible install commands in if/else under set -euo pipefail

Under `set -euo pipefail`, a bare command like `uv tool install 'litellm[proxy]'` will abort the entire script on failure, bypassing any intended soft-failure logic that follows. Always wrap such commands in an `if/else` block so failure is handled explicitly and the script can continue or emit a warning rather than crashing. Example pattern:

```bash
if uv tool install 'litellm[proxy]'; then
  secrets.write "litellm-install-method" "uv"
  log "LiteLLM installed via uv"
else
  warn "uv install failed — LiteLLM not installed"
fi
```

This applies to any install-script fallback path (Docker → uv, apt → brew, etc.) where failure should be a soft warning, not a hard abort.
