---
date: 2026-11-17
keywords: ["opencode", "tui-plugin", "sidebar", "plugin_enabled", "cli.json"]
aliases: ["Invalid V2 TUI plugin module", "disable sidebar context", "opencode.sidebar.context"]
trigger-on: ["opencode-tui-plugin", "opencode-sidebar-block"]
---

## 2.3 TUI parts are `Plugin.define`; sidebar blocks are plugin ids you disable by directive

An OpenCode 2.3 TUI part is the `./tui` export of a plugin package and must default-export `Plugin.define({ id: string, setup(ctx) })` from `@opencode/plugin/tui`. The pre-2.3 shape `{ id, tui }` that registers through `api.slots` is rejected at load with `Invalid V2 TUI plugin module` — the host validates `id` plus a `setup` function before anything mounts. Every built-in sidebar section is itself a bundled TUI plugin, so the lever for one is its **id**, not a slot name: `opencode.sidebar.context` (context percent + spend), `.todo`, `.mcp`, `.limit` in `sidebar.content`, `.footer` in `sidebar.footer`. Disable one with a `-<id>` directive in the **global** `~/.config/opencode/cli.json` `plugins` array (`{"plugins": ["-opencode.sidebar.context"]}`, order matters, later entries win). The `plugin_enabled: {"<id>": false}` map is the legacy `tui.json` key and does **not** reach the plugin list from `cli.json` — with it set, the block still mounts; the directive form is the one that works. v1 ids (`internal:sidebar-context`) match nothing on 2.x.
