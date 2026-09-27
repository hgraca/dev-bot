---
date: 2026-09-26
keywords: ["opencode-pty", "tui-plugin", "packaging", "sidebar"]
see: ["ADRs/20260926180001-pty-server-publishes-origin-for-discovery.md"]
---

## The PTY sidebar ships inside `opencode-pty`, not as a second plugin

The PTY sidebar was first built as dev-bot's own TUI plugin (`src/harnesses/opencode/pty-monitor/`), wired through the harness's TUI surface. The stakeholder's decision is that this is the wrong home: the widget belongs to the plugin it is a window onto, so installing `opencode-pty` is what delivers it — explicitly "not a new plugin, in the end it will be the same plugin". The port therefore adds a second publish target to the same package (`exports["./tui"]`, a separate file only because opencode rejects one module default-exporting both `server` and `tui`), and keeps one plugin identity: `id: opencode-pty`, panel label `PTY`, kv key `opencode-pty.sidebar.collapsed`. The consequence to remember is a consumer-side one: the server surface loads from `opencode.json` and the TUI surface from `tui.json`, so a hand-edited config must list the plugin in **both** (the CLI routes both detected targets automatically); dev-bot's own switch-over — deleting its local pty-monitor and pinning the released version — waits on an upstream release carrying the widget (dev-bot currently pins `0.3.6`, which has no `./tui`).
