---
date: 2026-06-12
keywords: ["devbot", "external-modules", "memory", "symlink", "bootstrap"]
see: ["ADRs/20260612-000000-external-module-storage-structure.md"]
---

## External module memory files symlinked individually into .agents/memory/

External modules' `memory/` paths from config are no longer symlinked as a module-named directory (`.agents/memory/<name>/`). Instead, the storage directory tree under `storage/external-agentic-modules/<name>/memory/` is walked and each file is symlinked individually at its configured destination path. For example, a file at `memory/bootstrap/karpathy-instructions.md` becomes `.agents/memory/bootstrap/karpathy-instructions.md` — the module name wrapper is removed. This matches how built-in modules' bootstrap files sit directly under `.agents/memory/bootstrap/` and lets external modules add their files alongside them without extra nesting.
