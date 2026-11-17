---
date: 2026-11-17
keywords: ["opencode", "plugins", "auto-load", "duplicate-plugin-id"]
aliases: ["duplicate plugin ID", "plugin listed twice", "opencode plugin not loading"]
trigger-on: ["opencode-plugin-loading", "opencode-duplicate-plugin"]
---

## `.opencode/plugins/` is auto-loaded — never list the same directory in `plugins`

OpenCode 2.x loads every plugin directory under `.opencode/plugins/` on its own. Adding a `plugins` entry that names one of those paths (`".opencode/plugins/on-hooks"`) registers the plugin a **second** time: the host keeps the first copy and fails the second with `Duplicate plugin ID: <id>`, which the TUI shows as a failed plugin while the real one works. The config array is for packages and plugin directories from _other_ locations only; a project-scoped plugin needs no entry at all. Same for a plugin directory the user dropped in by hand — the entry is always redundant. Symptom to recognise: `opencode plugin list` shows each plugin twice, one `local` (active) and one `package` (failed), plus a `WARN failed to check plugin update … Package checks only support registry and Git package specs` per start. Verified on 2.3: removing the `plugins` block leaves every plugin loaded once and active.
