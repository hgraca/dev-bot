---
date: 2026-11-17
keywords: ["devbot", "opencode-v2", "plugin", "spawn", "v2config"]
aliases: ["V2_SHARED_DIR missing", "mcp sync writes nothing", "helper stderr swallowed"]
---

# A plugin-spawned helper must resolve its own dependencies, and its stderr must be kept

## The trap

`hooks/mcp-sync.ts` shells out to `lib/v2config.py` for every config write. That process is spawned from the **running host**, so it inherits the host's environment, not the one `init.sh` exports when it calls the same helper — `V2_SHARED_DIR` is simply absent. The python then failed its very first import (`ModuleNotFoundError: No module named 'read_jsonc'`), exited 1, and wrote nothing.

## Why it stayed invisible

The hook piped `stderr` and never read it, so the failure looked like "nothing to do". Worse, the retry logic kept the old status to try again next poll, and each attempt took the lock — so the only visible symptom was `opencode.jsonc.mcp-sync.lock` appearing and vanishing every 2 s, while the TUI toggle never reached the config.

## The rules

Resolve every dependency from `__file__` (three levels up from `src/harnesses/opencode-v2/lib/` is `src/_shared`) and keep the env var as an override, never as the only route. Capture `stderr` on a non-zero exit and log the first distinct failure once; a helper that fails silently is worse than one that crashes. Distinguish "already correct" from "could not write" in the helper's exit codes (0 done, 2 not mine, 1 error) so the caller can tell a no-op from a bug.
