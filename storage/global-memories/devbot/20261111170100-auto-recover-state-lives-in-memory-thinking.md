---
date: 2026-11-11
keywords: ["devbot", "thinking", "auto-recover", "wrap-up"]
aliases: ["thinking cleanup deletes auto-recover state", "auto-recover lock file"]
trigger-on: ["thinking-directory-cleanup"]
---

## `devbot:auto-recover` keeps its lock and attempt counter in `memory/thinking/`

The auto-recover hook writes `.auto-recover-lock-<session>` and `.auto-recover-attempts-<session>.json` into `<devbot_dir>/memory/thinking/` — the same directory agents use for scratch drafts (`src/agentic/auto-recover/tools/auto-recover.ts`, plus the claudecode `on-stop-auto-recover.sh` and `on-posttooluse-auto-recover.sh` hooks). Any rule that sweeps `thinking/` at wrap-up must exclude those dotfiles explicitly: deleting them mid-run drops the retry counter and releases the lock, so auto-recovery restarts its attempt budget or races a second recovery against the first. Write the exclusion as a `.auto-recover-*` prefix carve-out, never as "everything in `thinking/`" — the two files are runtime state, not scratch.
