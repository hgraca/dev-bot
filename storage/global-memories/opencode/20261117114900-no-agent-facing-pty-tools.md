---
date: 2026-11-17
keywords: ["opencode", "pty", "terminal", "plugin-api"]
aliases: ["agent pty tools", "opencode terminal tool", "open_terminal"]
trigger-on: ["opencode-pty", "opencode-terminal"]
---

## 2.x has PTY infrastructure but no agent-facing PTY tools, and plugins cannot reach it

OpenCode 2.x ships no `pty_*` tool to the model: the built-in tool ids are `shell`, `read`, `write`, `edit`, `patch`, `glob`, `grep`, `todo`, `skill`, `question`, `subagent`, `webfetch`, `websearch`, `artifact`, `image-generate`, `schedule`. The PTY itself exists server-side (`/api/pty`, `/api/pty/{id}`, connect-token, plus an experimental persistent PTY with `/snapshot` and `/handoff`), and background commands live on `/api/shell` + `/api/shell/{id}/output` — that is what the built-in `shell` tool sits on. None of it is reachable from a plugin: the plugin context has no `pty` domain (agent, provider, model, command, integration, credential, mcp, plugin, reference, generate, permissions, session, skill, storage, tool, vcs, worktree, websearch, events), so a plugin that wants PTYs must embed a PTY library (`bun-pty`). The TUI additionally registers a `tui` toolset with `open_terminal` — "Open a terminal for the current session in the user's TUI, without taking keyboard focus" — which serves the human, not agent automation.
