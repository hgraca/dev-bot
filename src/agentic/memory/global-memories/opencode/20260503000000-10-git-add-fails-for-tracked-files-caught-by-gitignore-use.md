---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## `git add` fails for tracked files caught by gitignore — use `-f`

Files under `src/tools/opencode/` are tracked (force-added historically) but matched by `*opencode*` in `.gitignore`. Regular `git add` refuses; must use `git add -f`. Developer agents don't know this and report "gitignored, cannot commit" — the orchestrator must commit these files directly with `-f`.
