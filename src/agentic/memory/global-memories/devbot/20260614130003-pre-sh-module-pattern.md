---
date: 2026-06-14
keywords: ["devbot", "pre.sh", "module-pattern"]
---

## pre.sh Module Pattern

Only one module has `pre.sh`: codebase-index. It sources `functions.sh`, calls `_check_python3`, and reports success. No other module has one.

`pre.sh` is run by `bin/install.sh` and `bin/update.sh` — looped over all agentic modules. It's a prerequisites check gate; return non-zero to prevent the module from being installed.
