---
date: 2026-06-13
keywords: ["devbot", "remember-session", "watermark", "plugin", "memory"]
---

## Watermark I/O moved entirely into plugin — agents blind to watermark

The watermark mechanism was fully removed from agent knowledge. Previously, agents used the `watermark-session` skill and manually read/wrote `.agents/logs/remember-session.watermark.json`. Now all watermark I/O lives in the `on-session_idle-remember-session.ts` plugin.

Before prompt injection, the plugin calls `readWatermark(directory, sessionId)` to get the last capture timestamp. It prepends `Last capture: <timestamp>` or `Last capture: none` to the prompt text. The agent receives the timestamp in the prompt itself — never touches the watermark file. After the prompt completes, `writeWatermark()` records the new timestamp (unchanged behavior).

The standalone `watermark-session/SKILL.md` was deleted. All watermark references stripped from `remember-session/SKILL.md`, `remember-session.md` command, `memory-management/SKILL.md`, and bootstrap files. The test file was renamed to `remember-session_plugin_tests.bats` with 5 new `readWatermark()` test cases.
