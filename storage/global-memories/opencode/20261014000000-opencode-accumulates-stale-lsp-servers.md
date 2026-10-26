---
date: 2026-10-14
keywords: ["opencode", "language-server", "intelephense", "memory"]
---

## opencode accumulates one LSP server per directory and never tears down stale ones

A single long-running opencode session can spawn many language-server processes (observed: five `intelephense` PHP LSPs under one opencode parent, one per directory it walked into — the project root, git worktrees, even `vendor/` subdirectories) and leaves the stale ones running when the working directory changes. Each intelephense indexes its own tree into memory, so idle servers hold hundreds of MB of RSS plus multiple GB of swap — the dominant "unreleased" memory on a machine running opencode across several PHP workspaces. Diagnose with `pgrep -af intelephense` and `ps -o ppid= -p <pid>` (all share one opencode parent); reclaim with `kill <stale-pids>` — opencode respawns one only when you revisit that directory.

**Reclaim is now automatic (dev-bot PR #25, merged 2026-10-26).** `devbot:reconcile-work` runs `src/harnesses/opencode/lsp/reap.sh` first on every wrap-up, without asking. It walks the session's opencode process tree and kills a server only when it burned no CPU between two samples one second apart, or when its working directory no longer exists (a removed worktree) — a busy index is left alone, and the walk never leaves that one opencode process. Decisions land in `.agents/logs/lsp-reap.log`; `--dry-run` classifies without killing. `kill <stale-pids>` remains the manual fallback and is still the right move mid-session, when you do not want to wait for a wrap-up.
