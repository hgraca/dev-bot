---
date: 2026-09-19
keywords: ["opencode", "plugin-tools", "permission", "pty", "registry"]
trigger-on: ["opencode-plugin-permission", "opencode-tool-registry"]
---

## Permission rules gate plugin tools by removing them from the registry, never by prompting

A plugin tool built with the SDK's `tool()` gets no automatic permission check: `@opencode-ai/plugin`'s `tool()` is an identity function, so gating happens only if the plugin calls `context.ask()` itself, and third-party plugins usually do not. What still works is the registry filter — before an agent's tools are built, opencode computes `disabled(Object.keys(tools), merge(agent.permission, permission))` and keeps a tool only while `!disabledSet.has(name)`, so a rule with `action: "deny"` (e.g. `permission: { pty_spawn: deny }` in an agent file) removes that tool from that agent entirely. This is the only per-agent lever for plugin tools: `permission.bash: deny` does not reach them, because the one plugin that does check — opencode-pty's `checkCommandPermission` — reads the GLOBAL `permission.bash` from `client.config.get()` and never the per-agent ruleset, and treats `ask` as deny because a plugin cannot prompt. Corollary: to strip a capability from an agent, deny every tool that provides it by name — `bash: deny` alone leaves the PTY tools as an open shell.
