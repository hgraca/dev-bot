---
date: 2026-09-25
keywords: ["opencode", "tui", "kv", "tool-details", "defaults"]
trigger-on: ["opencode-tui-visibility-default", "opencode-tool-details-visibility"]
---

## opencode's TUI display toggles ("hide tool details" and siblings) are kv runtime state, not config — only a TUI plugin can set a default

`tool_details_visibility` (default `true` = shown) is not a key in any opencode config file: it lives in `~/.local/state/opencode/kv.json` and is toggled by the built-in `session.toggle.actions` command (keybind `keybinds.tool_details`, default `"none"`). The schemas confirm there is no config route — `https://opencode.ai/config.json` has no visibility key (its tool keys are `tools` for enable/disable and `tool_output` for truncation), and `https://opencode.ai/tui.json` offers only `keybinds` plus `plugin_enabled` built-in slots (sidebar context/files/footer/lsp/mcp/todo, home-footer/tips, notifications, plugin-manager) with **no** tool-details slot — so `opencode.jsonc` and `tui.json` cannot express the default and `plugin_enabled` cannot hide it. The only mechanism is a **TUI plugin** writing the same reactive kv store the built-in toggle writes (`api.kv.set`), which takes effect immediately and persists; dev-bot's harness ships `src/harnesses/opencode/tui-defaults/` for exactly that. Sibling display state is identical in kind: `generic_tool_output_visibility` (default `false`), `assistant_metadata_visibility`, `scrollbar_visible`, `diff_wrap_mode`, `animations_enabled`, `timestamps`, `thinking_mode`.
