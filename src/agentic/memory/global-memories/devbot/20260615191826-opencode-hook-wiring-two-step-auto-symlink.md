---
date: 2026-06-15
keywords: ["devbot", "opencode", "hook", "symlink", "init.sh"]
---

## OpenCode hook wiring is two-step: tool-level auto-symlink + module-level JSONC registration

The `create-devbot-module` skill says `install.sh` symlinks hooks into `.opencode/plugins/` — but the actual symlink is created by `src/tools/opencode/init.sh` scanning each module's `hooks/opencode/` directory (auto-discovery, idempotent). The module's own `init.sh` only registers the plugin path in `opencode.jsonc` via `_upsert_opencode_plugin`. Both must happen for the hook to be active: (1) symlink so the file exists at the registered path, (2) JSONC entry so opencode loads it. Missing either step → silent failure. The module's `install.sh` only handles OS dependencies; the module's `init.sh` only handles JSONC registration; the symlink is external (from the opencode tool init).
