---
date: 2026-05-02
keywords: ["graphify", "graph"]
---

## Git hooks backgrounded with `&` block Python MCP git server

Python's `subprocess` module waits until all inherited file descriptors close before returning. Git hooks that background processes with just `&` leave stdout/stderr FDs open, causing the MCP git server to hang until all hook children finish — making commits appear to take 30+ seconds.
Fix: Use `>/dev/null 2>&1 & disown` to close FDs and fully detach child processes from the parent shell. Applied in `src/tools/graphify/hooks-init.sh` for post-commit and post-checkout hooks.
