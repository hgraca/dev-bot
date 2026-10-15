---
date: 2026-10-14
keywords: ["opencode", "language-server", "intelephense", "memory"]
---

## opencode accumulates one LSP server per directory and never tears down stale ones

A single long-running opencode session can spawn many language-server processes (observed: five `intelephense` PHP LSPs under one opencode parent, one per directory it walked into — the project root, git worktrees, even `vendor/` subdirectories) and leaves the stale ones running when the working directory changes. Each intelephense indexes its own tree into memory, so idle servers hold hundreds of MB of RSS plus multiple GB of swap — the dominant "unreleased" memory on a machine running opencode across several PHP workspaces. Diagnose with `pgrep -af intelephense` and `ps -o ppid= -p <pid>` (all share one opencode parent); reclaim with `kill <stale-pids>` — opencode respawns one only when you revisit that directory.
