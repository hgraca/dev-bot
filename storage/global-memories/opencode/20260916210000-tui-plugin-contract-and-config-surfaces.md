---
date: 2026-09-16
keywords: ["opencode", "tui-plugin", "plugin-array", "tui-json", "config-surfaces"]
trigger-on: ["opencode-tui-plugin", "opencode-plugin-array"]
---

## opencode loads server and TUI plugins from different files, and only one is auto-discovered

`opencode.json`'s `plugin` array is the **server** plugin surface; TUI plugins load from `tui.json`'s `plugin` array. The split is enforced by schema, not convention: `https://opencode.ai/config.json` declares no `tui` key and sets `additionalProperties: false`, so a TUI plugin listed in `opencode.json` is schema-invalid and **opencode refuses to start**. Two traps beyond that. (1) TUI plugins are **not** auto-discovered — only files named in `tui.json` load, unlike hooks; a plugin with no config entry silently does nothing. (2) A TUI plugin module must **default-export an object `{ id, tui }`**; named exports fail with `"Plugin export is not a function"` (read the contract off a working plugin's `dist`, since `TuiPluginModule` reads like a two-named-export shape but is the default export's type). Also keep TUI-only modules **out of `.opencode/plugins/`** — that is the *server* plugin auto-discovery directory, so the server loader will be offered a module it cannot load and error. `tui.json` additionally accepts `plugin_enabled` (a `Record<string, boolean>`) to switch off opencode's own blocks by slot id: `internal:sidebar-context`, `-files`, `-footer`, `-lsp`, `-mcp`, `-todo`, `internal:home-footer`, `-tips`, `internal:notifications`, `internal:plugin-manager`. Those built-ins **do not persist** a collapsed state, so no option can default them collapsed or hide them — `plugin_enabled` removes them outright.
