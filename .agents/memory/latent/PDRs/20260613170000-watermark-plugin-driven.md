---
date: 2026-06-13
keywords: ["watermark", "plugin", "remember-session", "capture-timestamp"]
see: ["ADRs/20260613170000-watermark-agent-blindness.md"]
---

## Watermark mechanism moved from agent knowledge to plugin responsibility

The watermark-based session progress tracking is now fully plugin-driven. Agents no longer read, write, or know about the watermark file. Instead, the remember-session OpenCode plugin (`on-session_idle-remember-session.ts`) reads the last capture timestamp before injecting the prompt and passes it as `Last capture: <timestamp>` in the prompt text. After the agent completes its capture, the plugin writes the new watermark timestamp.

Rationale: removes a source of agent confusion (agents do not need to know about infrastructure plumbing), reduces skill complexity, and keeps the watermark implementation details encapsulated in one place (the plugin).
