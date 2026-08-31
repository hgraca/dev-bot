---
date: 2026-08-22
keywords: ["shell", "jq", "boolean", "stdout"]
trigger-on: ["jq-e-boolean-check"]
---

## jq -e boolean checks leak true/false to stdout in if conditions

`jq -e '…'` prints its boolean result (`true`/`false`) to stdout — the `-e` flag only sets the exit code (0 for true, 1 for false/null), it does not suppress output. So `if echo … | jq -e 'index("x") != null' 2>/dev/null; then` leaks a stray `false`/`true` line into the terminal on every evaluation. Redirect stdout too: `jq -e '…' >/dev/null 2>&1`. Hit across dev-bot's init/reset scripts (external-modules, graphify, tools-mcp, jetbrains, opencode/claudecode reset), which printed ~30 stray `false`/`true` lines during `devbot reinit`.
