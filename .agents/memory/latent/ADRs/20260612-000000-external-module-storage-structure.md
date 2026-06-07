---
date: 2026-06-12
keywords: ["devbot", "external-modules", "storage", "symlink", "init"]
---

## External modules now have full lifecycle via storage/external-agentic-modules/

External modules from `.devbot.jsonc` `modules` config are now wired into `storage/external-agentic-modules/<name>/` with the same structure as built-in `src/agentic/<module>/` modules. This enables them to participate in the full lifecycle: storage setup (symlinks to vendor repos), init script execution (`storage/external-agentic-modules/*/init.sh` runs during `bin/init.sh`), and memory folder linking (memory/ dirs symlinked into `.agents/memory/`). Config format unchanged — paths support both string values (directory symlinks) and object values (file-level symlinks with nested paths).
