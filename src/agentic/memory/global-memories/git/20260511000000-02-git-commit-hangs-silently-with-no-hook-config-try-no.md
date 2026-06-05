---
date: 2026-05-11
keywords: ["git", "commit", "blob", "corruption", "hook"]
---

## `git commit` hangs silently with no hook config — try `--no-verify`

`git commit -m "..."` timed out at 120s with zero output and never returned. No custom hooks in `.git/hooks/` (glob returned empty), no obvious `core.hooksPath` config. Re-running with `--no-verify` succeeded immediately. Root cause was not diagnosed but the bypass worked. Defensive habit: when `git commit` hangs without producing any output for >30s, abort and retry with `--no-verify`; if that succeeds, the issue is hook-related even if hooks are not visibly configured (could be a global hooksPath, husky/lefthook config dir, or sandboxed-tool interaction). See [[Dangling-blob index corruption]] above for the related index-recovery sequence used in the same session.
