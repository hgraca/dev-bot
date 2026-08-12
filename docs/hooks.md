---
layout: page
title: Hooks
description: OpenCode plugin hooks shipped by DevBot modules.
nav_section: docs
---

# Hooks

Hooks (OpenCode plugins) are TypeScript files under `hooks/opencode/` that fire automatically on lifecycle events — session start, provider errors, file saves, and tool execution. DevBot ships **12 hooks** across **9 modules**.

Each hook is named `on-<event>-<module>`, encoding the event it listens for and the module it belongs to. The table below is generated via `devbot list hooks -a` (includes disabled modules):

| Module              | Hook                                              |
| ------------------- | ------------------------------------------------- |
| agent-communication | on-session_idle-agent-communication               |
| auto-recover        | on-session_error-auto-recover                     |
| format-json         | on-file_edited-format-json                        |
| format-md           | on-file_edited-format-md                          |
| format-yml          | on-file_edited-format-yml                         |
| graphify            | on-session_created-graphify-update                |
| graphify            | on-tool_execute_after-git_commit-graphify-update  |
| guards              | on-tool_execute_before-guards                     |
| k8s                 | on-file_edited-lint-k8s                           |
| memory              | on-file_edited-reindex-memories                   |
| memory              | on-file_edited-reindex-passive-memories           |
| memory              | on-tool_execute_after-git_commit-remember-session |

Claude Code hooks live separately under each module's `hooks/claudecode/` (bash scripts registered in `~/.claude/settings.json`) — see [Plugins](/tools/plugins) for the event reference.
